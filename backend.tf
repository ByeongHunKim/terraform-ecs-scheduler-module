# ====================================================================
# Backend Configuration - Terraform Cloud
# - Separated for easy migration to different backends
# - Can be easily replaced with S3, local, or other backends
# ====================================================================
terraform {
  cloud {
    organization = "YOUR_ORGANIZATION_NAME"

    workspaces {
      name = "YOUR_WORKSPACE_NAME"
    }
  }
}

# Alternative backend configurations (commented out)
# Uncomment and modify as needed

# ====================================================================
# S3 Backend Alternative (uncomment if needed)
# ====================================================================
# terraform {
#   backend "s3" {
#     bucket         = "your-terraform-state-bucket"
#     key            = "dev/terraform.tfstate"
#     region         = "ap-northeast-2"
#     encrypt        = true
#     dynamodb_table = "terraform-lock-table"
#   }
# }

# ====================================================================
# Local Backend Alternative (uncomment if needed)
# ====================================================================
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }