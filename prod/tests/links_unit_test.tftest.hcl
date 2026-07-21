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

run "links_tables_named_per_environment_convention" {
  command = plan

  assert {
    condition     = local.links_table_name == "video-processor-links-db-prod"
    error_message = "Expected the Links table name to follow the video-processor-links-db-${var.environment} convention"
  }

  assert {
    condition     = local.link_events_table_name == "video-processor-link-events-db-prod"
    error_message = "Expected the LinkEvents table name to follow the video-processor-link-events-db-${var.environment} convention"
  }
}

run "links_tables_have_native_ttl_on_expires_at" {
  command = plan

  # 3-day retention is enforced by DynamoDB native TTL (ADR-002 v5) — this is
  # what replaced the scheduled cleanup job, so losing it silently would leave
  # links/events accumulating forever.
  assert {
    condition     = local.links_ttl_attribute == "expiresAt"
    error_message = "Expected TTL attribute to be expiresAt on both Links and LinkEvents (ADR-002 v5 — native TTL replaces the cleanup job)"
  }
}

run "links_table_has_user_gsi_for_listing_by_owner" {
  command = plan

  assert {
    condition     = local.links_user_gsi_name == "userId-index"
    error_message = "Expected the Links table GSI to be named userId-index — the links-service repository queries it by this exact name (GET /links/user/:id)"
  }
}