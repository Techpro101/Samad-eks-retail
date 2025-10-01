# terraform {
#   backend "s3" {
#     # These values will be provided during terraform init
#     # bucket         = "retail-store-terraform-state-xxxxx"
#     # key            = "terraform.tfstate"
#     # region         = "eu-north-1"
#     # dynamodb_table = "retail-store-terraform-locks"
#     # encrypt        = true
#   }
# }

terraform {
  backend "s3" {
    bucket         = "samad-eks-s3-bucket1001"
    key            = "state/eks-cluster.tfstate"
    region         = "us-east-1"
    dynamodb_table = "samad-eks-s3-bucket1001-locks"
    encrypt        = true
  }
}