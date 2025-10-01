#!/bin/bash

set -e

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -v, --vpc-id VPC_ID     Specify VPC ID to clean up"
    echo "  -r, --region REGION     AWS region (default: us-east-1)"
    echo "  -a, --auto              Auto-detect VPC from terraform state"
    echo "  -h, --help              Show this help message"
    exit 1
}

# Default values
REGION="us-east-1"
VPC_ID=""
AUTO_DETECT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--vpc-id)
            VPC_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -a|--auto)
            AUTO_DETECT=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Auto-detect VPC from terraform state
if [ "$AUTO_DETECT" = true ]; then
    echo "🔍 Auto-detecting VPC from terraform state..."
    VPC_ID=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type == "aws_vpc") | .values.id' | head -1)
    if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "null" ]; then
        echo "❌ Could not auto-detect VPC ID from terraform state"
        exit 1
    fi
    echo "✅ Detected VPC: $VPC_ID"
fi

# Validate VPC ID is provided
if [ -z "$VPC_ID" ]; then
    echo "❌ VPC ID is required. Use -v option or -a for auto-detection."
    usage
fi

# Verify VPC exists
if ! aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$REGION" >/dev/null 2>&1; then
    echo "❌ VPC $VPC_ID not found in region $REGION"
    exit 1
fi

echo "🧹 Cleaning up VPC dependencies for $VPC_ID in $REGION..."

# Function to check if resource exists and delete
cleanup_resource() {
    local resource_type="$1"
    local query="$2"
    local delete_cmd="$3"
    local wait_time="${4:-0}"
    
    echo "Cleaning up $resource_type..."
    local resources=$(aws ec2 $query --region "$REGION" 2>/dev/null | jq -r '.[] | select(. != null and . != "")' 2>/dev/null || echo "")
    
    if [ ! -z "$resources" ]; then
        echo "$resources" | while read -r resource; do
            if [ ! -z "$resource" ]; then
                echo "  Deleting $resource_type: $resource"
                eval "$delete_cmd $resource" || true
            fi
        done
        [ "$wait_time" -gt 0 ] && sleep "$wait_time"
    else
        echo "  No $resource_type found"
    fi
}

# 1. Terminate EC2 instances
cleanup_resource "EC2 instances" \
    "describe-instances --filters Name=vpc-id,Values=$VPC_ID Name=instance-state-name,Values=running,stopped --query 'Reservations[].Instances[].InstanceId' --output json" \
    "aws ec2 terminate-instances --instance-ids" \
    30

# 2. Delete EKS clusters
echo "Cleaning up EKS clusters..."
aws eks list-clusters --region "$REGION" --query 'clusters[]' --output text 2>/dev/null | while read -r cluster; do
    if [ ! -z "$cluster" ]; then
        cluster_vpc=$(aws eks describe-cluster --name "$cluster" --region "$REGION" --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || echo "")
        if [ "$cluster_vpc" = "$VPC_ID" ]; then
            echo "  Deleting EKS cluster: $cluster"
            aws eks delete-cluster --name "$cluster" --region "$REGION" || true
        fi
    fi
done

# 3. Delete RDS instances and clusters
echo "Cleaning up RDS resources..."
aws rds describe-db-instances --region "$REGION" --query 'DBInstances[].DBInstanceIdentifier' --output text 2>/dev/null | while read -r db; do
    if [ ! -z "$db" ]; then
        db_vpc=$(aws rds describe-db-instances --db-instance-identifier "$db" --region "$REGION" --query 'DBInstances[0].DBSubnetGroup.VpcId' --output text 2>/dev/null || echo "")
        if [ "$db_vpc" = "$VPC_ID" ]; then
            echo "  Deleting RDS instance: $db"
            aws rds delete-db-instance --db-instance-identifier "$db" --skip-final-snapshot --region "$REGION" || true
        fi
    fi
done

# 4. Delete Load Balancers
cleanup_resource "Load Balancers" \
    "describe-load-balancers --query 'LoadBalancers[?VpcId==\`$VPC_ID\`].LoadBalancerArn' --output json" \
    "aws elbv2 delete-load-balancer --load-balancer-arn"

# 5. Delete Target Groups
cleanup_resource "Target Groups" \
    "describe-target-groups --query 'TargetGroups[?VpcId==\`$VPC_ID\`].TargetGroupArn' --output json" \
    "aws elbv2 delete-target-group --target-group-arn"

# 6. Delete NAT Gateways
cleanup_resource "NAT Gateways" \
    "describe-nat-gateways --filter Name=vpc-id,Values=$VPC_ID --query 'NatGateways[?State!=\`deleted\`].NatGatewayId' --output json" \
    "aws ec2 delete-nat-gateway --nat-gateway-id" \
    60

# 7. Release Elastic IPs
echo "Releasing Elastic IPs..."
aws ec2 describe-addresses --region "$REGION" --filters "Name=domain,Values=vpc" --query 'Addresses[].AllocationId' --output text 2>/dev/null | while read -r eip; do
    if [ ! -z "$eip" ]; then
        echo "  Releasing EIP: $eip"
        aws ec2 release-address --allocation-id "$eip" --region "$REGION" || true
    fi
done

# 8. Delete VPC Endpoints
cleanup_resource "VPC Endpoints" \
    "describe-vpc-endpoints --filters Name=vpc-id,Values=$VPC_ID --query 'VpcEndpoints[].VpcEndpointId' --output json" \
    "aws ec2 delete-vpc-endpoint --vpc-endpoint-id"

# 9. Delete Network Interfaces
cleanup_resource "Network Interfaces" \
    "describe-network-interfaces --filters Name=vpc-id,Values=$VPC_ID --query 'NetworkInterfaces[?Status==\`available\`].NetworkInterfaceId' --output json" \
    "aws ec2 delete-network-interface --network-interface-id"

# 10. Delete Security Groups (except default)
cleanup_resource "Security Groups" \
    "describe-security-groups --filters Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[?GroupName!=\`default\`].GroupId' --output json" \
    "aws ec2 delete-security-group --group-id"

# 11. Delete Network ACLs (except default)
cleanup_resource "Network ACLs" \
    "describe-network-acls --filters Name=vpc-id,Values=$VPC_ID --query 'NetworkAcls[?IsDefault==\`false\`].NetworkAclId' --output json" \
    "aws ec2 delete-network-acl --network-acl-id"

# 12. Delete Subnets
cleanup_resource "Subnets" \
    "describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query 'Subnets[].SubnetId' --output json" \
    "aws ec2 delete-subnet --subnet-id"

# 13. Delete Route Tables (except main)
cleanup_resource "Route Tables" \
    "describe-route-tables --filters Name=vpc-id,Values=$VPC_ID --query 'RouteTables[?Associations[0].Main!=\`true\`].RouteTableId' --output json" \
    "aws ec2 delete-route-table --route-table-id"

# 14. Detach and Delete Internet Gateway
echo "Cleaning up Internet Gateway..."
aws ec2 describe-internet-gateways --region "$REGION" --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null | while read -r igw; do
    if [ ! -z "$igw" ]; then
        echo "  Detaching IGW: $igw"
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID" --region "$REGION" || true
        echo "  Deleting IGW: $igw"
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw" --region "$REGION" || true
    fi
done

echo "⏳ Waiting 60 seconds for final cleanup..."
sleep 60

# Verify VPC can be deleted
echo "🔍 Checking if VPC can now be deleted..."
if aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION" --dry-run 2>/dev/null; then
    echo "✅ VPC $VPC_ID is ready for deletion!"
else
    echo "⚠️  VPC may still have dependencies. Check AWS console for remaining resources."
fi

echo "✅ Cleanup complete. You can now run 'terraform destroy' or delete the VPC manually."