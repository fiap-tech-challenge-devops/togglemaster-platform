# cluster-bootstrap — Esteira de Addons EKS

Workflows GitHub Actions para instalar dependências de plataforma no cluster EKS do ToggleMaster.
Uso pessoal/lab — não é entrega versionada nesta fase.

---

## Pré-requisitos

- `terraform apply` executado com sucesso (pelo menos 1 node Ready no cluster)
- Outputs do Terraform disponíveis (`terraform output` na pasta `togglemaster-platform/terraform/`)
- ECR criado manualmente (fora desta esteira; a esteira nunca toca no ECR)
- Repositório GitHub com Actions habilitado

---

## Como publicar a esteira no GitHub

Os workflows GitHub Actions precisam estar em `.github/workflows/` **na raiz do repositório**
para serem reconhecidos pelo GitHub.

```bash
# A partir da raiz do repositório:
mkdir -p .github/workflows

cp togglemaster-platform/cluster-bootstrap/.github/workflows/install-addons.yml   .github/workflows/
cp togglemaster-platform/cluster-bootstrap/.github/workflows/uninstall-addons.yml .github/workflows/

git add .github/workflows/
git commit -m "ci: adiciona esteira de addons EKS"
git push
```

---

## Secrets GitHub necessários

Configure em **Settings → Secrets and variables → Actions → Repository secrets**:

| Secret | Descrição |
|--------|-----------|
| `AWS_OIDC_ROLE_ARN` | ARN da IAM Role assumida pelo runner via OIDC (ex: `arn:aws:iam::123456789012:role/github-actions-eks-bootstrap`) |

> O `AWS_ACCOUNT_ID` é obtido dinamicamente via `aws sts get-caller-identity` — não precisa de secret.

### IAM Role do runner (OIDC com GitHub)

Crie uma IAM Role com a seguinte trust policy (substitua `<ACCOUNT_ID>`, `<ORG>` e `<REPO>`):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:<ORG>/<REPO>:*"
      }
    }
  }]
}
```

Permissões mínimas necessárias na role do runner:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "iam:GetRole",
        "iam:CreateRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy",
        "iam:GetPolicy",
        "iam:CreatePolicy",
        "iam:ListAttachedRolePolicies",
        "sts:GetCallerIdentity",
        "elasticloadbalancing:*",
        "ec2:Describe*",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:CreateSecurityGroup",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "wafv2:*",
        "shield:*",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Como disparar a esteira

### Instalar addons

1. Vá em **Actions → EKS — Instalar Addons de Plataforma**
2. Clique em **Run workflow**
3. Preencha os inputs:

| Input | Obrigatório | Padrão | Descrição |
|-------|-------------|--------|-----------|
| `aws_region` | sim | `us-east-1` | Região do cluster |
| `cluster_name` | sim | `togglemaster-lab-eks` | Output `eks_cluster_name` do Terraform |

### Desinstalar addons

1. Vá em **Actions → EKS — Desinstalar Addons de Plataforma**
2. Preencha `aws_region` e `cluster_name`
3. No campo `confirm`, digite exatamente **`CONFIRMAR`** para prosseguir

> A desinstalação **não apaga** ECR, infra Terraform (RDS, Redis, EKS, SQS, DynamoDB) nem as
> IRSA roles criadas pela esteira. Remova as roles manualmente se desejar limpeza completa.

---

## Addons instalados (ordem de execução)

| Addon | Chart Helm | Namespace | IRSA role criada |
|-------|-----------|-----------|-----------------|
| AWS Load Balancer Controller | `eks/aws-load-balancer-controller` | `kube-system` | `<cluster>-lbc-irsa` |
| External Secrets Operator | `external-secrets/external-secrets` | `external-secrets` | `<cluster>-eso-irsa` |
| ClusterSecretStore | `kubectl apply` inline | cluster-scoped | — (usa ESO SA) |
| IngressClass ALB | criado pelo LBC chart | cluster-scoped | — |
| metrics-server | `metrics-server/metrics-server` | `kube-system` | — |

O ClusterSecretStore `aws-secrets-manager` aponta para o AWS Secrets Manager na região do cluster.
Os secrets RDS criados pelo Terraform (`togglemaster-lab/rds/auth`, `/rds/flags`, `/rds/targeting`)
ficam disponíveis para os microserviços via ExternalSecret.

---

## Validação pós-instalação

```bash
# Obter kubeconfig
aws eks update-kubeconfig --region us-east-1 --name togglemaster-lab-eks

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

terraform output eks_cluster_name          # nome do cluster
terraform output aws_region                # região
terraform output eks_update_kubeconfig_command

terraform output secret_arn_rds_auth       # ARN para testar ExternalSecret
terraform output secret_arn_rds_flags
terraform output secret_arn_rds_targeting
```
