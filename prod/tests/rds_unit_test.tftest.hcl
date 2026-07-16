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

run "rds_security_group_only_allows_eks_ingress" {
  command = plan

  assert {
    condition     = anytrue([for r in aws_security_group.rds.ingress : r.from_port == 5432 && r.to_port == 5432])
    error_message = "Expected the RDS security group to open only port 5432"
  }

  assert {
    condition     = anytrue([for r in aws_security_group.rds.ingress : contains(r.security_groups, data.aws_security_group.eks_cluster.id)])
    error_message = "Expected RDS ingress to source only from the EKS cluster security group, not a Lambda SG or 0.0.0.0/0"
  }
}

run "rds_identifier_follows_naming_convention" {
  command = plan

  assert {
    condition     = module.rds.db_instance_identifier == "video-processor-users-db-prod"
    error_message = "Expected the RDS identifier to follow the video-processor-users-db-${var.environment} convention"
  }
}
