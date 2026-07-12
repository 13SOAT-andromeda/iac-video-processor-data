# Spec — iac-video-processor-data

**Data:** 2026-07-11
**Status:** Draft — pronto para virar plano de implementação
**Repo antigo de referência:** `iac-tech-challenge-data`
**Spec guarda-chuva:** `docs/superpowers/specs/2026-07-11-video-processor-auth-infra-migration-design.md` (workspace raiz)

---

## 1. Responsabilidade

Provisionar a persistência de dados de autenticação/usuário:

- **RDS PostgreSQL** — tabela `users` (perfil administrativo, sem `password_hash`). **Não inclui `links`/`link_events` nesta fase** — essas tabelas entram quando o `links-service` for brainstormado (fora de escopo aqui).
- **DynamoDB** — tabela `auth-credentials` (fonte de verdade da credencial: `email`, `userId`, `password_hash`, `role`).

Contrato de dados completo em `service-users.md` (seção 2) e `service-authentication.md` (seção 5), copiados na íntegra em `video-processor-users-api` e `video-processor-authentication-api` respectivamente.

---

## 2. Módulos Terraform (Registry, confirmados via MCP em 2026-07-11)

| Módulo | Versão | Uso |
|---|---|---|
| `terraform-aws-modules/rds/aws` | 7.2.0 | Instância RDS Postgres (não Aurora — instância única, suficiente para o volume do hackathon) |
| `terraform-aws-modules/dynamodb-table/aws` | 5.5.0 | Tabela `auth-credentials` |
| provider `hashicorp/aws` | 6.54.0 | — |

Reconsultar o MCP do Terraform antes do `terraform init` real.

---

## 3. Estrutura de pastas

```
iac-video-processor-data/
├── dev/     # LocalStack, tflocal
└── prod/    # AWS real, backend S3 (key: video-processor-data/terraform.tfstate)
```

---

## 4. Recursos-chave

### RDS
- Engine: `postgres` · Instance class: `db.t3.micro` (volume do hackathon é baixo, ver arquitetura seção 4).
- DB name: `usersdb`.
- Multi-AZ: não (custo, não necessário para esta fase).
- Rede: subnets privadas + VPC obtidas via `data "aws_vpc"` (tag `Name = video-processor-vpc`) e `data "aws_subnets"` (tag `*-private-*`), publicadas por `iac-video-processor-infra` — mesmo padrão de acoplamento cross-repo do `iac-tech-challenge-data/aws/data.tf` (busca por tag, sem remote state).
- Security group: libera porta 5432 **somente** a partir da security group do Lambda `users-service` (único serviço com acesso de rede ao RDS, ver ADR-010 revisada).
- Migração de schema: tabela `users` conforme `service-users.md` seção 2 (`id uuid PK`, `name`, `email unique`, `role`, `document`, `created_at`, `updated_at` — **sem** `password_hash`).

### DynamoDB
- Tabela `auth-credentials`, billing mode `PAY_PER_REQUEST` (baixo volume, sem necessidade de capacidade provisionada).
- Partition key: `email` (string).
- Atributos (não-chave, não precisam estar no schema Terraform, só documentados): `userId`, `password_hash`, `role`.
- **Sem TTL** — diferente da tabela `links`/`link_events` (que teriam expiração de 3 dias), credenciais não expiram.
- IAM: só `users-service` recebe `PutItem`/`UpdateItem`/`DeleteItem`/`GetItem`; `authentication-api` recebe só `GetItem`.

---

## 5. Porta do repo antigo (`iac-tech-challenge-data`)

| Antigo | Novo | Observação |
|---|---|---|
| `modules/rds` | módulo de registry `terraform-aws-modules/rds/aws` | reescrito, não copiado |
| `modules/dynamodb` | módulo de registry `terraform-aws-modules/dynamodb-table/aws` | reescrito, não copiado |
| Tabela DynamoDB `user-authentication-token` (chave `token_id`) | Tabela `auth-credentials` (chave `email`) | **Não é o mesmo dado.** A antiga guardava token de sessão; a nova guarda a credencial (email/senha/role) que a Lambda `authentication` lê para emitir o JWT. Schema novo, não migração de dado. |
| `aws/` + `localstack/` | `prod/` + `dev/` | renomeado |

---

## 6. Pontos em aberto (resolver no plano de implementação)

1. Confirmar acesso de rede do `users-service` (Lambda em VPC) ao RDS sob eventuais restrições de conta de laboratório/estudante (mesma ressalva que a ADR-010 revisada do doc de arquitetura já registra) — se bloqueado, fallback é Aurora Serverless v2 + RDS Data API.
2. Nome/ARN do secret de credenciais do RDS (usuário mestre) no Secrets Manager — a definir junto com o plano.
3. Job agendado de limpeza (EventBridge Scheduler) não entra nesta fase — só se aplica quando `links`/`link_events` existirem.
