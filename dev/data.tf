data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = ["video-processor-vpc-local"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  filter {
    name   = "tag:Name"
    values = ["*-private-*"]
  }
}

data "aws_security_group" "eks_cluster" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  filter {
    name   = "tag:aws:eks:cluster-name"
    values = ["video-processor-eks-${var.environment}"]
  }
}
