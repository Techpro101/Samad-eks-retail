# Backend resources already exist and are managed outside Terraform
# S3 bucket: samad-eks-s3-bucket1001
# DynamoDB table: samad-eks-s3-bucket1001-locks

# Commented out to avoid conflicts with existing resources
# resource "aws_s3_bucket" "terraform_state" {
#   bucket = "samad-eks-s3-bucket1001"
# }

# resource "aws_dynamodb_table" "terraform_locks" {
#   name           = "samad-eks-s3-bucket1001-locks"
#   billing_mode   = "PAY_PER_REQUEST"
#   hash_key       = "LockID"

#   attribute {
#     name = "LockID"
#     type = "S"
#   }

#   server_side_encryption {
#     enabled = true
#   }
# }