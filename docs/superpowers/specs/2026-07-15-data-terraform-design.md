# Spec — Terraform de `iac-video-processor-data`

**Data:** 2026-07-15 (atualizado 2026-07-16 — colunas novas em `users` para progressive profiling; ADR-011; atualizado 2026-07-18 — coluna `role` removida do schema de `users`; ADR-012)
**Status:** Aprovado para virar plano de implementação
**Spec anterior (draft, parcialmente superada por esta):** `docs/superpowers/specs/2026-07-11-data-design.md`
**Spec guarda-chuva:** `docs/superpowers/specs/2026-07-11-video-processor-auth-infra-migration-design.md` (workspace raiz), atualizada em 2026-07-18
**RFCs de origem da atualização 2026-07-16:** `RFC_service-authentication.md`, `RFC_service-users.md` (ADR-011 — signup público + verificação de email + progressive profiling); reconciliação 2026-07-18 com `RFC_arquitetura-video-processing.md` (ver `docs/superpowers/specs/2026-07-18-notification-signup-integration-design.md`, ADR-012)

---

## 1. Responsabilidade

Provisionar a persistência de dados de autenticação/usuário:

- **RDS PostgreSQL** — tabela `users` (perfil administrativo, sem `password_hash`). Não inclui `links`/`link_events` nesta fase.
- **DynamoDB** — tabela de credenciais (`email`, `userId`, `password_hash`, `role`).

Contrato de dados completo em `service-users.md` (seção 2) e `service-authentication.md` (seção 5).

## 2. O que mudou desde o draft de 2026-07-11

O draft original (seção 4, ponto 6.1) ainda descrevia o `users-service` como Lambda. A spec guarda-chuva foi atualizada em 2026-07-13: **`users-api` roda como container no EKS**, atrás do ALB compartilhado, não como Lambda. Isso muda de onde vem o acesso de rede ao RDS — da SG do EKS, não de uma SG de Lambda. Esta spec finaliza esse ponto e os demais itens que o draft deixava em aberto (nomes, gerenciamento de senha, bucket de state).

## 3. Estrutura de pastas

Espelha o padrão já validado em `iac-video-processor-infra`:

```
iac-video-processor-data/
├── dev/     # LocalStack, tflocal, credenciais fake, endpoints localhost:4566
└── prod/    # AWS real
```

## 4. Backend de state (prod/)

Bucket S3 **compartilhado** entre os 3 repos IaC (`infra`, `data`, `gateway`): `video-processor-bucket-andromeda` (já existe, criado durante o bootstrap de `iac-video-processor-infra`). Key própria: `video-processor-data/terraform.tfstate`. `use_lockfile = true` (Terraform `>= 1.11`), mesmo padrão do `infra`.

**Motivo do compartilhamento:** a conta AWS Academy usada é resetada a cada ~4h (sessão do Learner Lab). Um bucket por repo triplicaria o trabalho de bootstrap manual a cada sessão nova; um bucket único com keys diferentes por repo resolve isso com uma única recriação.

## 5. Lookup cross-repo (sem remote state, por tag)

Mesmo padrão de acoplamento do antigo `iac-tech-challenge-data/aws/data.tf` — busca por tag, sem remote state entre repos:

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

A tag `aws:eks:cluster-name` é aplicada automaticamente pela AWS na security group que o EKS cria (confirmado no cluster real em produção: `sg-01ce56f32dc3606f4`, tag `aws:eks:cluster-name = video-processor-eks-prod`) — estável entre recriações do cluster, diferente do `Name` (que carrega um sufixo aleatório).

**Implicação:** o cluster EKS (ou ao menos sua VPC/SG) precisa existir no momento do `apply` deste repo, já que a SG do RDS referencia a SG do EKS diretamente.

## 6. RDS

Módulo: `terraform-aws-modules/rds/aws ~> 7.2` (confirmado via MCP do Terraform, versão atual 7.2.0).

| Campo | Valor |
|---|---|
| `identifier` | `video-processor-users-db-${var.environment}` |
| `engine` | `postgres` |
| `engine_version` | `16` |
| `family` | `postgres16` |
| `instance_class` | `db.t3.micro` |
| `allocated_storage` | `20` |
| `db_name` | `usersdb` |
| `username` | `dbadmin` |
| `manage_master_user_password` | `true` (padrão do módulo já é `true` — explícito aqui por clareza) |
| `multi_az` | `false` |
| `publicly_accessible` | `false` |
| `skip_final_snapshot` | `true` |
| `deletion_protection` | `false` (padrão do módulo — necessário para permitir `terraform destroy` no ciclo de 4h) |
| `create_db_subnet_group` | `true`, subnets = `data.aws_subnets.private.ids` |
| `vpc_security_group_ids` | SG própria (`aws_security_group.rds`, recurso nativo, não o módulo) |

**Security group do RDS** (recurso nativo, mesmo padrão do `iac-tech-challenge-data/modules/rds`):
- Egress: todo tráfego liberado (`0.0.0.0/0`).
- Ingress porta 5432: **somente** a partir de `data.aws_security_group.eks_cluster.id` (decisão da seção de brainstorming — reflete que `users-api` é o único serviço com acesso ao RDS hoje, rodando em container no EKS).

**Senha do usuário mestre:** gerenciada 100% pela AWS via Secrets Manager (`manage_master_user_password = true`), sem nenhum valor sensível passando pelo Terraform ou pelo `state`. O output `db_instance_master_user_secret_arn` do módulo é reexposto como output deste repo (`rds_master_user_secret_arn`). Acesso local: `aws secretsmanager get-secret-value --secret-id <arn> --query SecretString --output text | jq .` retorna `username`/`password`/`host`/`port`/`dbname` — executado pelo usuário diretamente, nunca pelo agente (ver `aws-core:aws-secrets-manager`: chamadas de `get-secret-value` não devem expor valor em texto puro no contexto do agente).

**Migração de schema (atualizado 2026-07-16 — progressive profiling, ADR-011; atualizado 2026-07-18 — `role` removida, ADR-012; atualizado 2026-07-18 continuação — `phone`/`address` removidas de escopo):** a versão original desta seção previa colunas `phone`/`address` para progressive profiling — **revertido na mesma sessão de brainstorming**: `name`/`email`/`document` (coletados por completo no signup) passam a ser os únicos dados de perfil armazenados; não há mais nenhum dado preenchido progressivamente depois do signup. Schema completo: `id uuid PK`, `name`, `email unique`, `document`, `created_at`, `updated_at` — sem `password_hash`, sem `role` (fica exclusiva em `auth-credentials`/DynamoDB, dono `authentication` — nenhuma rota de `users-api` decide algo com base em `role`, ver ADR-012) e sem `phone`/`address`. A linha é criada **exclusivamente** por um worker de `users-api`, reativamente, a partir do evento `UserSignedUp` publicado por `authentication` no signup (ver `docs/superpowers/specs/2026-07-18-notification-signup-integration-design.md`) — não existe mais nenhuma rota HTTP de criação/edição self-service (`GET/PUT /users/me` foram removidos). Execução da migração continua fora deste repo (roda a partir do `video-processor-users-api`, não do Terraform).

## 7. DynamoDB

Módulo: `terraform-aws-modules/dynamodb-table/aws ~> 5.5` (confirmado via MCP, versão atual 5.5.0).

| Campo | Valor |
|---|---|
| `name` | `video-processor-auth-db-${var.environment}` |
| `billing_mode` | `PAY_PER_REQUEST` |
| `hash_key` | `email` (string) |
| `ttl_enabled` | `false` (credenciais não expiram, diferente de `links`/`link_events` futuros) |

Atributos não-chave (`userId`, `password_hash`, `role`, `email_verified` — este último novo na atualização 2026-07-16, ADR-011) não entram no schema Terraform — são schemaless, só documentados no contrato de dados de `video-processor-authentication-api`. Sem GSI nesta fase (nenhum padrão de consulta do spec de serviço exige lookup por `userId`).

## 8. Fora de escopo / limitações conhecidas

- **IAM das tabelas/instância:** cada serviço consumidor gerencia sua própria policy de acesso em sua pasta `terraform/` local (mesmo padrão estrutural já usado por `video-processor-authorizer` para sua própria role de execução, embora ali não haja acesso a dado). Este repo só cria os recursos de dado e expõe ARNs/endpoints via output.
- **Limitação de ambiente (não deste repo):** o EKS usa `LabRole` compartilhado por todos os nós, sem IRSA configurado. Isso significa que não é possível, hoje, restringir por pod o acesso somente do `users-service` ao DynamoDB como o contrato de dados idealiza (seção 4 do spec de 2026-07-11) — qualquer pod no node group herda as permissões amplas do `LabRole`. Registrado como débito técnico da fase, não resolvido aqui.
- **Migração de schema SQL e job de limpeza agendado** (`links`/`link_events`) permanecem fora de escopo, conforme spec guarda-chuva seção 9.

## 9. Testes

`terraform test` com `mock_provider`, mesmo padrão do `iac-video-processor-infra`:
- Mock de `data.aws_vpc`, `data.aws_subnets`, `data.aws_security_group` (formato de ID/ARN válido, já que o módulo RDS valida formato em alguns campos).
- Asserts: nome do RDS identifier e da tabela DynamoDB seguem a convenção `video-processor-*-${var.environment}`; ingress da SG do RDS aponta para `data.aws_security_group.eks_cluster.id`; `manage_master_user_password = true`; `ttl_enabled = false` na tabela.

## 10. Convenções herdadas (spec guarda-chuva, seção 7)

- Prefixo `video-processor-*` em todo recurso.
- Tags padrão: `Project = video-processor`, `Environment = ${var.environment}`.
- Provider `hashicorp/aws ~> 6.54` (mesma versão do `infra`).
