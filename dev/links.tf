# Persistência do links-service (video-processor-link-api) — arquitetura §4,
# ADR-002 v5: DynamoDB dedicado com TTL nativo de 3 dias (campo expiresAt),
# substituindo qualquer job de limpeza agendado. Escrita exclusiva do
# links-service (ADR-007).

locals {
  links_table_name       = "video-processor-links-db-${var.environment}"
  link_events_table_name = "video-processor-link-events-db-${var.environment}"
  links_ttl_attribute    = "expiresAt"
  links_user_gsi_name    = "userId-index"
}

module "links_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 5.5"

  name     = local.links_table_name
  hash_key = "linkId"

  attributes = [
    {
      name = "linkId"
      type = "S"
    },
    {
      name = "userId"
      type = "S"
    }
  ]

  # GET /links/user/:id — consulta por dono do link
  global_secondary_indexes = [
    {
      name            = local.links_user_gsi_name
      hash_key        = "userId"
      projection_type = "ALL"
    }
  ]

  billing_mode       = "PAY_PER_REQUEST"
  ttl_enabled        = true
  ttl_attribute_name = local.links_ttl_attribute

  tags = {
    Project     = "video-processor"
    Environment = var.environment
  }
}

module "link_events_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 5.5"

  name      = local.link_events_table_name
  hash_key  = "linkId"
  range_key = "createdAt"

  attributes = [
    {
      name = "linkId"
      type = "S"
    },
    {
      name = "createdAt"
      type = "S"
    }
  ]

  billing_mode       = "PAY_PER_REQUEST"
  ttl_enabled        = true
  ttl_attribute_name = local.links_ttl_attribute

  tags = {
    Project     = "video-processor"
    Environment = var.environment
  }
}
