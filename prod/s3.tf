# Bucket de vídeos — upload direto do browser (presigned PUT emitida pelo
# links-service) e resultado do processamento (zip gerado pelo futuro
# video-processor-converter). Layout de chave: ${linkId}/raw/... e
# ${linkId}/processed/... — como o prefixo raiz é o linkId, a retenção de
# 3 dias (arquitetura §9) se aplica ao bucket inteiro, sem filtro por prefixo.
#
# A notificação ObjectCreated -> SQS video-processing-queue fica para a etapa
# do converter (dono da fila de trabalho) — sem notification config aqui.

locals {
  videos_bucket_name = "video-processor-videos-andromeda-${var.environment}"
}

resource "aws_s3_bucket" "videos" {
  bucket = local.videos_bucket_name

  # Ciclo de ~4h do AWS Academy: permite terraform destroy sem esvaziar à mão.
  force_destroy = true

  tags = {
    Project     = "video-processor"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "videos" {
  bucket = aws_s3_bucket.videos.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "videos" {
  bucket = aws_s3_bucket.videos.id

  rule {
    id     = "expire-videos-after-3-days"
    status = "Enabled"

    filter {}

    expiration {
      days = 3
    }
  }
}

# CORS só é necessário aqui: o upload vai direto do browser para o bucket.
# O API Gateway não precisa de CORS (chamadas partem do servidor Next.js — BFF).
resource "aws_s3_bucket_cors_configuration" "videos" {
  bucket = aws_s3_bucket.videos.id

  cors_rule {
    allowed_methods = ["PUT", "GET", "HEAD"]
    allowed_origins = var.videos_bucket_cors_allowed_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}
