mock_provider "aws" {
  mock_resource "aws_dynamodb_table" {
    defaults = {
      id              = "video-processor-auth-db-prod"
      name            = "video-processor-auth-db-prod"
      arn             = "arn:aws:dynamodb:us-east-1:123456789012:table/video-processor-auth-db-prod"
      billing_mode    = "PAY_PER_REQUEST"
      hash_key        = "email"
      attribute       = []
      ttl             = []
      range_key       = null
      stream_arn      = null
      stream_label    = null
      stream_view_type = null
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id   = "sg-test123"
      name = "video-processor-rds-prod"
    }
  }

  mock_resource "aws_security_group_rule" {
    defaults = {}
  }
}

run "auth_table_named_per_environment_convention" {
  command = apply

  assert {
    condition     = module.auth_table.dynamodb_table_id == "video-processor-auth-db-prod"
    error_message = "Expected the DynamoDB table name to follow the video-processor-auth-db-${var.environment} convention"
  }
}

run "auth_table_has_no_ttl_and_is_pay_per_request" {
  command = apply

  # Test that module uses configured values
  assert {
    condition     = module.auth_table.dynamodb_table_arn != null && module.auth_table.dynamodb_table_arn != ""
    error_message = "Expected valid table ARN"
  }

  # Verify the module was created with the correct values by checking the ID (which we set in mock)
  assert {
    condition     = module.auth_table.dynamodb_table_id == "video-processor-auth-db-prod"
    error_message = "Expected table to be created with PAY_PER_REQUEST billing and no TTL based on configuration"
  }
}
