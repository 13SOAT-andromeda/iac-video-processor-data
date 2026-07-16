output "rds_identifier" {
  description = "The RDS instance identifier"
  value       = module.rds.db_instance_identifier
}

output "rds_endpoint" {
  description = "The RDS connection endpoint (host:port)"
  value       = module.rds.db_instance_endpoint
}

output "rds_master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the RDS master user credentials"
  value       = module.rds.db_instance_master_user_secret_arn
}

output "auth_table_name" {
  description = "Name of the DynamoDB auth-credentials table"
  value       = module.auth_table.dynamodb_table_id
}

output "auth_table_arn" {
  description = "ARN of the DynamoDB auth-credentials table"
  value       = module.auth_table.dynamodb_table_arn
}
