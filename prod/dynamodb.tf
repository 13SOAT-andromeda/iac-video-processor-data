locals {
  auth_table_name         = "video-processor-auth-db-${var.environment}"
  auth_table_hash_key     = "email"
  auth_table_billing_mode = "PAY_PER_REQUEST"
  auth_table_ttl_enabled  = false
}

module "auth_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 5.5"

  name     = local.auth_table_name
  hash_key = local.auth_table_hash_key

  attributes = [
    {
      name = local.auth_table_hash_key
      type = "S"
    }
  ]

  billing_mode = local.auth_table_billing_mode
  ttl_enabled  = local.auth_table_ttl_enabled

  tags = {
    Project     = "video-processor"
    Environment = var.environment
  }
}
