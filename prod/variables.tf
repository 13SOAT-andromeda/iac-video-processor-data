variable "environment" {
  description = "Environment name (used in resource naming/tags)"
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "videos_bucket_cors_allowed_origins" {
  description = "Allowed origins for browser->S3 direct upload (restrict to the frontend origin once it exists — never * in real production)"
  type        = list(string)
  default     = ["*"]
}
