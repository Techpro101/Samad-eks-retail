#!/bin/bash

set -e

REGION="us-east-1"
VPC_ID="vpc-0ea7234a043116d14"

echo "🧹 Cleaning up VPC dependencies for $VPC_ID..."

# 1. Terminate EC2 instances
echo "Terminating EC2 instances..."
aws ec2 describe-instances --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,stopped" --query 'Reservations[].Instances[].InstanceId' --output text | while read instance_id; do
  if [ ! -z "$instance_id" ]; then
    echo "Terminating instance: $instance_id"
    aws ec2 terminate-instances --instance-ids $instance_id --region $REGION || true
  fi
done

# 2. Delete Load Balancers
echo "Deleting Load Balancers..."
aws elbv2 describe-load-balancers --region $REGION --query 'LoadBalancers[?VpcId==`'$VPC_ID'`].LoadBalancerArn' --output text | while read lb_arn; do
  if [ ! -z "$lb_arn" ]; then
    echo "Deleting LB: $lb_arn"
    aws elbv2 delete-load-balancer --load-balancer-arn $lb_arn --region $REGION || true
  fi
done

# 3. Delete Target Groups
echo "Deleting Target Groups..."
aws elbv2 describe-target-groups --region $REGION --query 'TargetGroups[?VpcId==`'$VPC_ID'`].TargetGroupArn' --output text | while read tg_arn; do
  if [ ! -z "$tg_arn" ]; then
    echo "Deleting TG: $tg_arn"
    aws elbv2 delete-target-group --target-group-arn $tg_arn --region $REGION || true
  fi
done

# 4. Delete NAT Gateways
echo "Deleting NAT Gateways..."
aws ec2 describe-nat-gateways --region $REGION --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text | while read nat_id; do
  if [ ! -z "$nat_id" ]; then
    echo "Deleting NAT Gateway: $nat_id"
    aws ec2 delete-nat-gateway --nat-gateway-id $nat_id --region $REGION || true
  fi
done

# 5. Release Elastic IPs associated with VPC
echo "Releasing Elastic IPs..."
aws ec2 describe-addresses --region $REGION --filters "Name=domain,Values=vpc" --query 'Addresses[].AllocationId' --output text | while read alloc_id; do
  if [ ! -z "$alloc_id" ]; then
    echo "Releasing EIP: $alloc_id"
    aws ec2 release-address --allocation-id $alloc_id --region $REGION || true
  fi
done

# 6. Delete VPC Endpoints
echo "Deleting VPC Endpoints..."
aws ec2 describe-vpc-endpoints --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'VpcEndpoints[].VpcEndpointId' --output text | while read endpoint_id; do
  if [ ! -z "$endpoint_id" ]; then
    echo "Deleting VPC Endpoint: $endpoint_id"
    aws ec2 delete-vpc-endpoint --vpc-endpoint-id $endpoint_id --region $REGION || true
  fi
done

# 7. Delete Network ACL entries and NACLs (except default)
echo "Deleting Network ACLs..."
aws ec2 describe-network-acls --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkAcls[?IsDefault==`false`].NetworkAclId' --output text | while read nacl_id; do
  if [ ! -z "$nacl_id" ]; then
    echo "Deleting NACL: $nacl_id"
    aws ec2 delete-network-acl --network-acl-id $nacl_id --region $REGION || true
  fi
done

# 8. Delete Network Interfaces
echo "Deleting Network Interfaces..."
aws ec2 describe-network-interfaces --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' --output text | while read eni_id; do
  if [ ! -z "$eni_id" ]; then
    echo "Deleting ENI: $eni_id"
    aws ec2 delete-network-interface --network-interface-id $eni_id --region $REGION || true
  fi
done

# 9. Delete Security Groups (except default)
echo "Deleting Security Groups..."
aws ec2 describe-security-groups --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text | while read sg_id; do
  if [ ! -z "$sg_id" ]; then
    echo "Deleting SG: $sg_id"
    aws ec2 delete-security-group --group-id $sg_id --region $REGION || true
  fi
done

# 10. Delete Subnets
echo "Deleting Subnets..."
aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text | while read subnet_id; do
  if [ ! -z "$subnet_id" ]; then
    echo "Deleting Subnet: $subnet_id"
    aws ec2 delete-subnet --subnet-id $subnet_id --region $REGION || true
  fi
done

# 11. Delete Route Tables (except main)
echo "Deleting Route Tables..."
aws ec2 describe-route-tables --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text | while read rt_id; do
  if [ ! -z "$rt_id" ]; then
    echo "Deleting Route Table: $rt_id"
    aws ec2 delete-route-table --route-table-id $rt_id --region $REGION || true
  fi
done

# 12. Detach and Delete Internet Gateway
echo "Deleting Internet Gateway..."
aws ec2 describe-internet-gateways --region $REGION --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[].InternetGatewayId' --output text | while read igw_id; do
  if [ ! -z "$igw_id" ]; then
    echo "Detaching and deleting IGW: $igw_id"
    aws ec2 detach-internet-gateway --internet-gateway-id $igw_id --vpc-id $VPC_ID --region $REGION || true
    aws ec2 delete-internet-gateway --internet-gateway-id $igw_id --region $REGION || true
  fi
done

echo "⏳ Waiting 90 seconds for all resources to be fully deleted..."
sleep 90

echo "✅ VPC dependencies cleaned up. You can now run terraform destroy."