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

run "cross_repo_lookups_use_expected_tags" {
  command = plan

  assert {
    condition     = anytrue([for f in data.aws_vpc.selected.filter : f.name == "tag:Name" && contains(f.values, "video-processor-vpc")])
    error_message = "Expected the VPC lookup to filter on tag:Name with value video-processor-vpc"
  }

  assert {
    condition     = anytrue([for f in data.aws_security_group.eks_cluster.filter : f.name == "tag:aws:eks:cluster-name" && contains(f.values, "video-processor-eks-prod")])
    error_message = "Expected the EKS security group lookup to filter on tag:aws:eks:cluster-name with value video-processor-eks-prod (default environment)"
  }
}
