module "auth_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 5.5"

  name     = "video-processor-auth-db-${var.environment}"
  hash_key = "email"

  attributes = [
    {
      name = "email"
      type = "S"
    }
  ]

  billing_mode = "PAY_PER_REQUEST"
  ttl_enabled  = false

  tags = {
    Project     = "video-processor"
    Environment = var.environment
  }
}
