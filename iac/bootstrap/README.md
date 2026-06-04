# Stage 0 — bootstrap

Cria, **uma única vez e localmente** (com credenciais de admin), o que a esteira precisa:

- Bucket S3 do state remoto (`<system>-iac-tfstate-<account_id>`, versionado + criptografado)
- Tabela DynamoDB de lock (`<system>-iac-tflock`)
- OIDC provider do GitHub + IAM role (`github-actions-iac`) que a esteira assume

State deste stage é **local** (ele cria o backend que os outros usam).

## Uso

```bash
cd iac/bootstrap
terraform init
terraform apply

# Anote os outputs:
terraform output state_bucket
terraform output github_actions_role_arn   # → secret AWS_OIDC_ROLE_ARN no GitHub
terraform output backend_config_hint        # → args de init dos stages infra/addons
```

Depois configure no repositório GitHub o secret **`AWS_OIDC_ROLE_ARN`** com a role.

> `github_repository` default é `fiap-tech-challenge-devops/togglemaster-platform` —
> ajuste para o seu `<org>/<repo>` real antes do apply.
>
> A role recebe **AdministratorAccess** (lab). Em produção, restrinja ao mínimo.
