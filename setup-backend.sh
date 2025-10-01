#!/bin/bash

# Setup S3 backend and DynamoDB table for Terraform state

echo "Setting up Terraform backend resources..."

# Create S3 bucket for state
aws s3 mb s3://samad-eks-s3-bucket1001 --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket samad-eks-s3-bucket1001 \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket samad-eks-s3-bucket1001 \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name samad-eks-s3-bucket1001-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1

echo "Backend resources created successfully!"
echo "S3 Bucket: samad-eks-s3-bucket1001"
echo "DynamoDB Table: samad-eks-s3-bucket1001-locks"