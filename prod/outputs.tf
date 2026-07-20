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

output "links_table_name" {
  description = "Name of the DynamoDB Links table (exclusive writer: links-service)"
  value       = module.links_table.dynamodb_table_id
}

output "links_table_arn" {
  description = "ARN of the DynamoDB Links table"
  value       = module.links_table.dynamodb_table_arn
}

output "link_events_table_name" {
  description = "Name of the DynamoDB LinkEvents table (exclusive writer: links-service)"
  value       = module.link_events_table.dynamodb_table_id
}

output "link_events_table_arn" {
  description = "ARN of the DynamoDB LinkEvents table"
  value       = module.link_events_table.dynamodb_table_arn
}

output "videos_bucket_name" {
  description = "Name of the S3 videos bucket (raw uploads + processed zips, 3-day lifecycle)"
  value       = aws_s3_bucket.videos.id
}

output "videos_bucket_arn" {
  description = "ARN of the S3 videos bucket"
  value       = aws_s3_bucket.videos.arn
}
