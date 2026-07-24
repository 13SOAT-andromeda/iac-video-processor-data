resource "aws_security_group" "rds" {
  name        = "video-processor-rds-${var.environment}"
  description = "Allow PostgreSQL access only from the EKS cluster"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    description     = "PostgreSQL from the EKS cluster"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [data.aws_security_group.eks_cluster.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project     = "video-processor"
    Environment = var.environment
  }
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 7.2"

  identifier = "video-processor-users-db-${var.environment}"

  engine               = "postgres"
  engine_version       = "16"
  family               = "postgres16"
  major_engine_version = "16"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20

  db_name  = "usersdb"
  username = "dbadmin"

  manage_master_user_password = true

  multi_az            = false
  publicly_accessible = false
  skip_final_snapshot = true

  # Performance Insights uses an AWS-managed service-linked role, so it does
  # not require iam:CreateRole (unlike Enhanced Monitoring's
  # create_monitoring_role, which stays disabled on this AWS Academy Lab
  # account).
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # pg_stat_statements backs Datadog's Database Monitoring (query samples,
  # per-statement stats). shared_preload_libraries is a static parameter —
  # takes effect immediately here only because it's set on the parameter
  # group the instance is *created* with; changing it on an existing
  # instance needs a reboot (apply_method=pending-reboot below covers that
  # case too, for future changes).
  create_db_parameter_group = true
  parameters = [
    {
      name         = "shared_preload_libraries"
      value        = "pg_stat_statements"
      apply_method = "pending-reboot"
    },
    {
      name  = "pg_stat_statements.track"
      value = "all"
    },
    {
      name  = "track_activity_query_size"
      value = "4096"
    },
    {
      name  = "track_io_timing"
      value = "1"
    },
  ]

  create_db_subnet_group = true
  subnet_ids             = data.aws_subnets.private.ids
  vpc_security_group_ids = [aws_security_group.rds.id]

  tags = {
    Project     = "video-processor"
    Environment = var.environment
  }
}
