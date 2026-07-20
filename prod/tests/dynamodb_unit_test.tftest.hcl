mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = {
      id = "vpc-0123456789abcdef0"
    }
  }

  mock_data "aws_subnets" {
    defaults = {
      ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    }
  }

  mock_data "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }
}

run "auth_table_named_per_environment_convention" {
  command = plan

  assert {
    condition     = local.auth_table_name == "video-processor-auth-db-prod"
    error_message = "Expected the DynamoDB table name to follow the video-processor-auth-db-${var.environment} convention"
  }
}

run "auth_table_has_no_ttl_and_is_pay_per_request" {
  command = plan

  assert {
    condition     = local.auth_table_ttl_enabled == false
    error_message = "Expected the auth credentials table to have TTL disabled — credentials don't expire, unlike future links/link_events tables"
  }

  assert {
    condition     = local.auth_table_billing_mode == "PAY_PER_REQUEST"
    error_message = "Expected PAY_PER_REQUEST billing mode (low volume, no need for provisioned capacity)"
  }
}
