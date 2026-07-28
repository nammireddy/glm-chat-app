###############################################################################
# Remote State Backend
#
# Uncomment and fill in the values below to enable S3 remote state.
# Ensure the S3 bucket and DynamoDB table exist before running `terraform init`.
###############################################################################

# terraform {
#   backend "s3" {
#     bucket         = "your-terraform-state-bucket"
#     key            = "glm-chat/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "terraform-lock"
#   }
# }
