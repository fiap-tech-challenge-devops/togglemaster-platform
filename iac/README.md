# IaC — ToggleMaster (staged)

Infra do ToggleMaster em **stages**, consumindo os módulos de
`github.com/vitorfprado/terraform-aws-modules`. A separação existe porque os addons
(helm/kubernetes) **não podem ser planejados antes do cluster existir** — então cada stage
é um `terraform apply` independente, com seu próprio state.

```
iac/
├── bootstrap/   stage 0 — S3 + DynamoDB (state remoto) + OIDC role da esteira   [rodar 1x local]
├── infra/       stage 1 — VPC, EKS(SPOT), RDS×3, Redis, SQS, DynamoDB, IRSA, secrets
└── addons/      stage 2 — metrics-server, AWS LB Controller (ALB), ESO + ClusterSecretStore
```

## Handoff entre stages

O stage 1 publica no **SSM Parameter Store** (`/togglemaster/iac/*`): `cluster-name`,
`oidc-provider-arn`, `oidc-provider-url`, `vpc-id`. O stage 2 lê esses parâmetros (sem
`terraform_remote_state`) para configurar os providers helm/kubernetes e o módulo `eks/addons`.

## Ordem de execução

### 1. Bootstrap (uma vez, local, com admin)

```bash
cd iac/bootstrap
terraform init && terraform apply
terraform output github_actions_role_arn   # → secret AWS_OIDC_ROLE_ARN no GitHub
terraform output backend_config_hint
```

### 2. Esteira (GitHub Actions)

- **`IaC — Apply`** (`workflow_dispatch`): `action=plan` mostra; `action=apply` sobe
  stage 1 → stage 2 em sequência.
- **`IaC — Destroy`**: derruba stage 2 → stage 1 (ordem reversa), exige confirmar `DESTROY`.

Pré-requisito: secret **`AWS_OIDC_ROLE_ARN`** no repositório (output do bootstrap).

## Rodar local (opcional)

```bash
cd iac/infra   # ou iac/addons
terraform init \
  -backend-config="bucket=togglemaster-iac-tfstate-<ACCOUNT_ID>" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=togglemaster-iac-tflock"
terraform plan
```

> O stage 2 só dá `plan`/`apply` coerente **depois** do stage 1 aplicado (precisa do cluster
> e dos parâmetros SSM). Validação de sintaxe isolada: `terraform validate` após
> `terraform init -backend=false`.
