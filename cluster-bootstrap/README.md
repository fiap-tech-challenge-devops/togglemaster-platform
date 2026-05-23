# cluster-bootstrap — Esteira de Addons EKS

Workflows GitHub Actions para instalar dependências de plataforma no cluster EKS do ToggleMaster.
Uso pessoal/lab — não é entrega versionada nesta fase.

---

## Pré-requisitos

- `terraform apply` executado com sucesso (pelo menos 1 node Ready no cluster)
- IRSA de plataforma criadas pelo Terraform (`platform_irsa.tf`): `<cluster>-lbc-irsa` e `<cluster>-eso-irsa`
- Outputs do Terraform disponíveis (`terraform output` na pasta `togglemaster-platform/terraform/`)
- ECR criado manualmente (fora desta esteira; a esteira nunca toca no ECR)
- Repositório GitHub com Actions habilitado

---

## Localização dos workflows

Os workflows estão em `.github/workflows/` na raiz do repositório e são reconhecidos
diretamente pelo GitHub Actions — nenhum passo extra necessário.

---

## Secrets GitHub necessários

Configure em **Settings → Secrets and variables → Actions → Repository secrets**:

| Secret | Descrição |
|--------|-----------|
| `AWS_OIDC_ROLE_ARN` | ARN da role OIDC — use `terraform output -raw github_actions_role_arn` após o apply |

> O `AWS_ACCOUNT_ID` é obtido dinamicamente via `aws sts get-caller-identity` — não precisa de secret.

### IAM Role do runner (gerenciada pelo Terraform)

A role `github_actions` (`github_actions.tf`), policy mínima (só `eks:DescribeCluster`) e o **EKS Access Entry**
(`AmazonEKSClusterAdminPolicy`) são criados no `terraform apply`. IRSA do LBC e ESO ficam em
`platform_irsa.tf` — a esteira **não cria IAM**, apenas instala charts Helm e aplica manifests.

O cluster usa `authentication_mode = API_AND_CONFIG_MAP`, então `kubectl get nodes` na esteira funciona
sem configurar `aws-auth` manualmente.

Variáveis em `terraform.tfvars`:

- Repositório OIDC fixo em `locals.tf`: `fiap-tech-challenge-devops/togglemaster-platform`
- `github_actions_role_name` — padrão `github-actions-eks-bootstrap` (mesmo nome da role criada no Portal)
- `create_github_oidc_provider` — `false` se o provedor OIDC do GitHub já existir na conta

**Migrar role criada à mão (uma vez):**

```bash
cd togglemaster-platform/terraform
terraform import aws_iam_role.github_actions github-actions-eks-bootstrap
```

Depois do apply, confira o ARN e atualize o secret `AWS_OIDC_ROLE_ARN` se mudou.

---

## Como disparar a esteira

### Instalar addons

1. Vá em **Actions → EKS — Instalar Addons de Plataforma**
2. Clique em **Run workflow**
3. Preencha os inputs:

| Input | Obrigatório | Padrão | Descrição |
|-------|-------------|--------|-----------|
| `aws_region` | sim | `us-east-1` | Região do cluster |
| `cluster_name` | sim | `eks-togglemaster` | Output `eks_cluster_name` do Terraform |

### Desinstalar addons

1. Vá em **Actions → EKS — Desinstalar Addons de Plataforma**
2. Preencha `aws_region` e `cluster_name`
3. No campo `confirm`, digite exatamente **`CONFIRMAR`** para prosseguir

> A desinstalação **não apaga** ECR nem infra Terraform (RDS, Redis, EKS, SQS, DynamoDB, IRSA).

---

## Addons instalados (ordem de execução)

| Addon | Chart Helm | Namespace | IRSA (Terraform) |
|-------|-----------|-----------|------------------|
| AWS Load Balancer Controller | `eks/aws-load-balancer-controller` | `kube-system` | `<cluster>-lbc-irsa` |
| External Secrets Operator | `external-secrets/external-secrets` | `external-secrets` | `<cluster>-eso-irsa` |
| ClusterSecretStore | `kubectl apply` inline | cluster-scoped | usa SA do ESO |
| IngressClass ALB | criado pelo LBC chart | cluster-scoped | — |
| metrics-server | `metrics-server/metrics-server` | `kube-system` | — |

O ClusterSecretStore `aws-secrets-manager` aponta para o AWS Secrets Manager na região do cluster.
Os secrets RDS criados pelo Terraform (`togglemaster/rds/auth`, `/rds/flags`, `/rds/targeting`)
ficam disponíveis para os microserviços via ExternalSecret.

---

## Validação pós-instalação

```bash
# Obter kubeconfig
aws eks update-kubeconfig --region us-east-1 --name eks-togglemaster

# AWS Load Balancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# External Secrets Operator
kubectl get pods -n external-secrets

# ClusterSecretStore (Status deve ser Ready=True)
kubectl get clustersecretstore aws-secrets-manager -o wide

# IngressClass ALB
kubectl get ingressclass

# metrics-server
kubectl top nodes
```

---

## Outputs Terraform úteis

```bash
cd togglemaster-platform/terraform

terraform output eks_cluster_name              # eks-togglemaster
terraform output -raw github_actions_role_arn  # secret AWS_OIDC_ROLE_ARN
terraform output -raw iam_role_arn_lbc_irsa      # IRSA LBC (antes da esteira)
terraform output -raw iam_role_arn_eso_irsa      # IRSA ESO (antes da esteira)
terraform output aws_region                    # região
terraform output vpc_id
terraform output eks_update_kubeconfig_command

terraform output secret_arn_rds_auth       # ARN para testar ExternalSecret
terraform output secret_arn_rds_flags
terraform output secret_arn_rds_targeting
```
