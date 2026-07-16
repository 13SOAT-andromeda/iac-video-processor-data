# iac-video-processor-data Terraform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Terraform for `iac-video-processor-data` (RDS Postgres + DynamoDB) in both `dev/` (LocalStack) and `prod/` (real AWS), per the approved spec.

**Architecture:** Two independent Terraform root modules (`dev/`, `prod/`), each looking up the VPC/subnets/EKS security group from `iac-video-processor-infra` by tag (no remote state), then calling the `terraform-aws-modules/rds/aws` and `terraform-aws-modules/dynamodb-table/aws` registry modules. `prod/` uses a real S3 backend (shared bucket with the other two IaC repos); `dev/` uses the same S3 backend type pointed at LocalStack, matching the pattern already used in `iac-video-processor-infra`.

**Tech Stack:** Terraform `>= 1.11`, provider `hashicorp/aws ~> 6.54`, `terraform-aws-modules/rds/aws ~> 7.2` (7.2.0 confirmed via Terraform MCP), `terraform-aws-modules/dynamodb-table/aws ~> 5.5` (5.5.0 confirmed via Terraform MCP), `terraform test` with `mock_provider` for unit-level wiring checks.

## Global Constraints

- Terraform `required_version >= 1.11` (S3 backend `use_lockfile` native locking, matches `iac-video-processor-infra`).
- Provider `hashicorp/aws ~> 6.54`.
- `terraform-aws-modules/rds/aws ~> 7.2`, `terraform-aws-modules/dynamodb-table/aws ~> 5.5` — re-verify via Terraform MCP if a real `terraform init` is run much later than this plan was written.
- Every resource gets tags `Project = "video-processor"`, `Environment = var.environment`.
- Resource naming prefix: `video-processor-*`.
- `prod/` backend: S3 bucket `video-processor-bucket-andromeda` (shared with `iac-video-processor-infra`/`iac-video-processor-gateway`), key `video-processor-data/terraform.tfstate`, `use_lockfile = true`.
- `dev/` backend: same S3 bucket family as `iac-video-processor-infra`'s `dev/` (`video-processor-bucket-andromeda-local`), LocalStack endpoints (`http://localhost:4566`), fake `test`/`test` credentials — copy the exact `backend "s3" { ... }` / `provider "aws" { ... }` block from `iac-video-processor-infra/dev/main.tf`, only the `key` changes.
- Cross-repo VPC name lookup: `video-processor-vpc` in `prod/`, `video-processor-vpc-local` in `dev/` (matches `iac-video-processor-infra`'s VPC naming per environment).
- EKS cluster name for the security group lookup: `video-processor-eks-${var.environment}` (`video-processor-eks-prod` in `prod/`, `video-processor-eks-localstack` in `dev/`).
- RDS identifier: `video-processor-users-db-${var.environment}`. DynamoDB table name: `video-processor-auth-db-${var.environment}`.
- No IAM resources of any kind are created in this repo (no `LabRole` reference either — unlike `iac-video-processor-infra`, this repo never touches IAM).

---

## Task 1: Repo scaffold — `.gitignore` + `prod/` terraform/provider/variables

**Files:**
- Create: `.gitignore`
- Create: `prod/main.tf`
- Create: `prod/variables.tf`

**Interfaces:**
- Produces: `var.environment` (default `"prod"`), `var.region` (default `"us-east-1"`) — consumed by every later `prod/` task.

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# Terraform
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
terraform.tfvars
terraform.tfvars.json
*.tfplan
tfplan*.out

# Agents
.claude/
```

- [ ] **Step 2: Create `prod/variables.tf`**

```hcl
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
```

- [ ] **Step 3: Create `prod/main.tf`**

```hcl
terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.54"
    }
  }

  backend "s3" {
    bucket       = "video-processor-bucket-andromeda"
    key          = "video-processor-data/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Terraform   = "true"
      Environment = var.environment
      Project     = "video-processor"
    }
  }
}
```

- [ ] **Step 4: Validate (no backend yet, no state to touch)**

Run: `cd prod && terraform init -backend=false && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add .gitignore prod/main.tf prod/variables.tf
git commit -m "chore: bootstrap prod/ terraform skeleton (backend, provider, variables)"
```

---

## Task 2: Cross-repo data lookups (`prod/data.tf`) + unit test

**Files:**
- Create: `prod/data.tf`
- Create: `prod/tests/data_unit_test.tftest.hcl`

**Interfaces:**
- Consumes: nothing from earlier tasks besides `var.environment` (Task 1).
- Produces: `data.aws_vpc.selected` (`.id`), `data.aws_subnets.private` (`.ids`), `data.aws_security_group.eks_cluster` (`.id`) — consumed by Task 3 (RDS security group + subnet group).

- [ ] **Step 1: Write the failing test**

Create `prod/tests/data_unit_test.tftest.hcl`:

```hcl
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
    condition     = data.aws_vpc.selected.filter[0].name == "tag:Name"
    error_message = "Expected the VPC lookup to filter on tag:Name"
  }

  assert {
    condition     = data.aws_vpc.selected.filter[0].values[0] == "video-processor-vpc"
    error_message = "Expected the VPC lookup to target the video-processor-vpc tag value in prod"
  }

  assert {
    condition     = data.aws_security_group.eks_cluster.filter[1].name == "tag:aws:eks:cluster-name"
    error_message = "Expected the EKS security group lookup to filter on the aws:eks:cluster-name tag, not Name (which carries a random suffix)"
  }

  assert {
    condition     = data.aws_security_group.eks_cluster.filter[1].values[0] == "video-processor-eks-prod"
    error_message = "Expected the EKS security group lookup to target video-processor-eks-prod (default environment)"
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd prod && terraform test`
Expected: FAIL — `Reference to undeclared resource` (`data.aws_vpc.selected` does not exist yet).

- [ ] **Step 3: Write `prod/data.tf`**

```hcl
data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = ["video-processor-vpc"]
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd prod && terraform test`
Expected: `Success! 1 passed, 0 failed.`

- [ ] **Step 5: Commit**

```bash
git add prod/data.tf prod/tests/data_unit_test.tftest.hcl
git commit -m "feat: add cross-repo VPC/subnet/EKS-SG lookups by tag"
```

---

## Task 3: RDS security group + module (`prod/rds.tf`) + unit test

**Files:**
- Create: `prod/rds.tf`
- Modify: `prod/tests/data_unit_test.tftest.hcl` → rename usage pattern by adding a new file instead: `prod/tests/rds_unit_test.tftest.hcl` (create)

**Interfaces:**
- Consumes: `data.aws_vpc.selected.id`, `data.aws_subnets.private.ids`, `data.aws_security_group.eks_cluster.id` (Task 2).
- Produces: `aws_security_group.rds.id`, `module.rds.db_instance_identifier`, `module.rds.db_instance_endpoint`, `module.rds.db_instance_master_user_secret_arn` — consumed by Task 5 (outputs).

- [ ] **Step 1: Write the failing test**

Create `prod/tests/rds_unit_test.tftest.hcl`:

```hcl
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
```

**Note on `manage_master_user_password`:** this is a static boolean argument passed into a black-box registry module, not something `mock_provider` can meaningfully verify (mocked computed outputs don't reflect real provider validation logic tied to that flag). Its correctness is verified by code review of `prod/rds.tf` Step 3 below, not by a `terraform test` assertion.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd prod && terraform test`
Expected: FAIL — `Reference to undeclared resource` (`aws_security_group.rds` / `module.rds` do not exist yet).

- [ ] **Step 3: Write `prod/rds.tf`**

```hcl
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

  engine                = "postgres"
  engine_version        = "16"
  family                = "postgres16"
  major_engine_version  = "16"
  instance_class        = "db.t3.micro"
  allocated_storage      = 20

  db_name  = "usersdb"
  username = "dbadmin"

  manage_master_user_password = true

  multi_az             = false
  publicly_accessible  = false
  skip_final_snapshot  = true

  create_db_subnet_group = true
  subnet_ids             = data.aws_subnets.private.ids
  vpc_security_group_ids = [aws_security_group.rds.id]

  tags = {
    Project     = "video-processor"
    Environment = var.environment
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd prod && terraform test`
Expected: `Success! 3 passed, 0 failed.` (2 from this task's file + 1 from Task 2's file)

- [ ] **Step 5: Commit**

```bash
git add prod/rds.tf prod/tests/rds_unit_test.tftest.hcl
git commit -m "feat: add RDS Postgres instance restricted to EKS cluster ingress"
```

---

## Task 4: DynamoDB table (`prod/dynamodb.tf`) + unit test

**Files:**
- Create: `prod/dynamodb.tf`
- Create: `prod/tests/dynamodb_unit_test.tftest.hcl`

**Interfaces:**
- Consumes: nothing from earlier tasks (independent of RDS/data lookups).
- Produces: `module.auth_table.dynamodb_table_id`, `module.auth_table.dynamodb_table_arn` — consumed by Task 5 (outputs).

- [ ] **Step 1: Write the failing test**

Create `prod/tests/dynamodb_unit_test.tftest.hcl`:

```hcl
run "auth_table_named_per_environment_convention" {
  command = plan

  assert {
    condition     = module.auth_table.dynamodb_table_id == "video-processor-auth-db-prod"
    error_message = "Expected the DynamoDB table name to follow the video-processor-auth-db-${var.environment} convention"
  }
}

run "auth_table_has_no_ttl_and_is_pay_per_request" {
  command = plan

  assert {
    condition     = length([for r in aws_dynamodb_table.this : r if r.ttl[0].enabled]) == 0
    error_message = "Expected the auth credentials table to have TTL disabled — credentials don't expire, unlike future links/link_events tables"
  }

  assert {
    condition     = one(aws_dynamodb_table.this[*].billing_mode) == "PAY_PER_REQUEST"
    error_message = "Expected PAY_PER_REQUEST billing mode (low volume, no need for provisioned capacity)"
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd prod && terraform test`
Expected: FAIL — `Reference to undeclared resource` (`module.auth_table` does not exist yet).

- [ ] **Step 3: Write `prod/dynamodb.tf`**

```hcl
module "auth_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 5.5"

  name     = "video-processor-auth-db-${var.environment}"
  hash_key = "email"

  attributes = [
    {
      name = "email"
      type = "S"
    }
  ]

  billing_mode = "PAY_PER_REQUEST"
  ttl_enabled  = false

  tags = {
    Project     = "video-processor"
    Environment = var.environment
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd prod && terraform test`
Expected: `Success! 5 passed, 0 failed.`

- [ ] **Step 5: Commit**

```bash
git add prod/dynamodb.tf prod/tests/dynamodb_unit_test.tftest.hcl
git commit -m "feat: add auth-credentials DynamoDB table (PAY_PER_REQUEST, no TTL)"
```

---

## Task 5: Outputs (`prod/outputs.tf`)

**Files:**
- Create: `prod/outputs.tf`

**Interfaces:**
- Consumes: `module.rds.db_instance_identifier`, `module.rds.db_instance_endpoint`, `module.rds.db_instance_master_user_secret_arn`, `module.auth_table.dynamodb_table_id`, `module.auth_table.dynamodb_table_arn` (Tasks 3–4).
- Produces: nothing further consumed inside this repo — these are the repo's public contract for anyone reading Terraform outputs (e.g. a human running `terraform output`).

- [ ] **Step 1: Write `prod/outputs.tf`**

```hcl
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
```

- [ ] **Step 2: Run the full test suite and validate**

Run: `cd prod && terraform test && terraform validate`
Expected: All `run` blocks pass; `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add prod/outputs.tf
git commit -m "feat: expose RDS/DynamoDB outputs (endpoint, secret ARN, table name/ARN)"
```

---

## Task 6: `dev/` (LocalStack) mirror

**Files:**
- Create: `dev/main.tf`
- Create: `dev/variables.tf`
- Create: `dev/data.tf`
- Create: `dev/rds.tf`
- Create: `dev/dynamodb.tf`
- Create: `dev/outputs.tf`

**Interfaces:**
- Produces: same shape as `prod/` (Tasks 1–5), just against LocalStack — no new interfaces, this task is a parameterized copy.

- [ ] **Step 1: Create `dev/variables.tf`**

```hcl
variable "environment" {
  description = "Environment name (used in resource naming/tags)"
  type        = string
  default     = "localstack"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
```

- [ ] **Step 2: Create `dev/main.tf`**

```hcl
terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.54"
    }
  }

  backend "s3" {
    bucket = "video-processor-bucket-andromeda-local"
    key    = "video-processor-data/terraform.tfstate"
    region = "us-east-1"
    endpoints = {
      s3  = "http://localhost:4566"
      iam = "http://localhost:4566"
      sts = "http://localhost:4566"
    }
    access_key                  = "test"
    secret_key                  = "test"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = false
    use_path_style              = true
  }
}

provider "aws" {
  region                      = var.region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = false
  s3_use_path_style           = true

  endpoints {
    ec2            = "http://localhost:4566"
    rds            = "http://localhost:4566"
    dynamodb       = "http://localhost:4566"
    sts            = "http://localhost:4566"
    secretsmanager = "http://localhost:4566"
  }

  default_tags {
    tags = {
      Terraform   = "true"
      Environment = var.environment
      Project     = "video-processor"
    }
  }
}
```

- [ ] **Step 3: Create `dev/data.tf`**

```hcl
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
```

- [ ] **Step 4: Create `dev/rds.tf`**

```hcl
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

  create_db_subnet_group = true
  subnet_ids              = data.aws_subnets.private.ids
  vpc_security_group_ids  = [aws_security_group.rds.id]

  tags = {
    Project     = "video-processor"
    Environment = var.environment
  }
}
```

- [ ] **Step 5: Create `dev/dynamodb.tf`**

```hcl
module "auth_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 5.5"

  name     = "video-processor-auth-db-${var.environment}"
  hash_key = "email"

  attributes = [
    {
      name = "email"
      type = "S"
    }
  ]

  billing_mode = "PAY_PER_REQUEST"
  ttl_enabled  = false

  tags = {
    Project     = "video-processor"
    Environment = var.environment
  }
}
```

- [ ] **Step 6: Create `dev/outputs.tf`**

```hcl
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
```

- [ ] **Step 7: Validate**

Run: `cd dev && terraform init -backend=false && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 8: Commit**

```bash
git add dev/
git commit -m "feat: mirror prod/ RDS+DynamoDB terraform for dev/ (LocalStack)"
```

---

## Task 7: Full-suite sanity check

**Files:** none (verification only)

- [ ] **Step 1: Re-verify module versions are still current**

Run (via Terraform MCP, not shell): `get_latest_module_version` for `terraform-aws-modules/rds/aws` and `terraform-aws-modules/dynamodb-table/aws`. If newer than `7.2.0`/`5.5.0`, bump the `version` constraint in `prod/rds.tf`, `prod/dynamodb.tf`, `dev/rds.tf`, `dev/dynamodb.tf` accordingly before proceeding.

- [ ] **Step 2: Run the full prod/ test suite**

Run: `cd prod && terraform test`
Expected: `Success! 5 passed, 0 failed.`

- [ ] **Step 3: Validate both roots**

Run: `cd prod && terraform validate && cd ../dev && terraform validate`
Expected: `Success! The configuration is valid.` for both.

- [ ] **Step 4: Confirm no plaintext secrets were introduced**

Run: `grep -rn "password" prod/ dev/ --include=*.tf`
Expected: no matches other than the `manage_master_user_password = true` argument name itself — no `var.db_password` or literal password string anywhere.

This plan stops here — it does not include a real `terraform apply` against the AWS Academy account. That is a follow-up manual/interactive step once the EKS cluster (from `iac-video-processor-infra`) is confirmed up, since the RDS security group depends on it existing.
