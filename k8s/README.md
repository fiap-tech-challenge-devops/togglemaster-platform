# ToggleMaster — Manifestos Kubernetes (Fase 1)

Manifestos básicos para o cluster `eks-togglemaster` (us-east-1). Fase 1 cobre Deployments,
Services e ExternalSecrets. Ingress, HPA e NetworkPolicy ficam para fases seguintes (ver
`ai/K8S-PLATFORM-CONTEXT.md`).

---

## Pré-requisitos

- Cluster `eks-togglemaster` up; addons instalados via `cluster-bootstrap/` (ESO, LBC, metrics-server)
- `ClusterSecretStore` `aws-secrets-manager` com `Status: Ready=True`
- Secrets RDS criados pelo Terraform em `togglemaster/rds/auth`, `/rds/flags`, `/rds/targeting`
- `kubectl` configurado: `aws eks update-kubeconfig --region us-east-1 --name eks-togglemaster`

---

## Placeholders a preencher antes do apply

| Placeholder | Como obter |
|---|---|
| `PLACEHOLDER_SQS_QUEUE_URL` | `terraform output -raw sqs_queue_url` |
| `PLACEHOLDER_REDIS_URL` | `terraform output -raw redis_url` (formato `redis://<endpoint>:6379/0`) |
| `PLACEHOLDER_IAM_ROLE_ARN_EVALUATION_IRSA` | `terraform output -raw iam_role_arn_evaluation_irsa` |
| `PLACEHOLDER_IAM_ROLE_ARN_ANALYTICS_IRSA` | `terraform output -raw iam_role_arn_analytics_irsa` |
| `PLACEHOLDER_MASTER_KEY` | Gerar: `openssl rand -hex 32`; guardar em local seguro |
| `PLACEHOLDER_SERVICE_API_KEY` | Gerar após auth subir: `POST /admin/keys` via port-forward |

Editar os arquivos listados abaixo e substituir cada placeholder antes do apply:

```
configmap-common.yaml                        → SQS_URL, REDIS_URL
auth-service/secret-master-key.yaml         → MASTER_KEY
evaluation-service/serviceaccount.yaml      → IRSA ARN evaluation
evaluation-service/secret-api-key.yaml      → SERVICE_API_KEY (preencher após auth subir)
analytics-service/serviceaccount.yaml       → IRSA ARN analytics
```

### IRSA e namespace togglemaster

O trust policy atual no Terraform referencia `system:serviceaccount:default:<nome>`. Como os
Deployments estão no namespace `togglemaster`, é necessário atualizar `terraform/iam.tf` para
ambas as roles (evaluation e analytics) antes de testar SQS/DynamoDB:

```hcl
# Em iam.tf — alterar nas condições do trust policy:
# "system:serviceaccount:default:evaluation-service"  →  "system:serviceaccount:togglemaster:evaluation-service"
# "system:serviceaccount:default:analytics-service"   →  "system:serviceaccount:togglemaster:analytics-service"
```

Depois: `terraform apply` antes do apply dos manifestos IRSA.

---

## Ordem de apply

```bash
# 1. Namespace (sempre primeiro)
kubectl apply -f togglemaster-platform/k8s/namespace.yaml

# 2. ConfigMap e Secrets manuais
kubectl apply -f togglemaster-platform/k8s/configmap-common.yaml
kubectl apply -f togglemaster-platform/k8s/auth-service/secret-master-key.yaml
kubectl apply -f togglemaster-platform/k8s/evaluation-service/secret-api-key.yaml

# 3. ServiceAccounts IRSA (antes dos Deployments que as usam)
kubectl apply -f togglemaster-platform/k8s/evaluation-service/serviceaccount.yaml
kubectl apply -f togglemaster-platform/k8s/analytics-service/serviceaccount.yaml

# 4. ExternalSecrets (ESO cria os Secrets K8s; aguardar Status: Ready)
kubectl apply -f togglemaster-platform/k8s/auth-service/externalsecret.yaml
kubectl apply -f togglemaster-platform/k8s/flag-service/externalsecret.yaml
kubectl apply -f togglemaster-platform/k8s/targeting-service/externalsecret.yaml

# Verificar sync antes de continuar:
kubectl get externalsecret -n togglemaster

# 5. auth-service (dependência de flag, targeting e evaluation)
kubectl apply -f togglemaster-platform/k8s/auth-service/deployment.yaml
kubectl apply -f togglemaster-platform/k8s/auth-service/service.yaml

# Aguardar Ready:
kubectl rollout status deployment/auth-service -n togglemaster

# 6. flag-service e targeting-service (podem subir em paralelo)
kubectl apply -f togglemaster-platform/k8s/flag-service/deployment.yaml
kubectl apply -f togglemaster-platform/k8s/flag-service/service.yaml
kubectl apply -f togglemaster-platform/k8s/targeting-service/deployment.yaml
kubectl apply -f togglemaster-platform/k8s/targeting-service/service.yaml

kubectl rollout status deployment/flag-service -n togglemaster
kubectl rollout status deployment/targeting-service -n togglemaster

# 7. Gerar SERVICE_API_KEY e atualizar secret-api-key.yaml, depois re-aplicar
kubectl port-forward svc/auth-service 8001:8001 -n togglemaster &
# Em outro terminal:
curl -X POST http://localhost:8001/admin/keys -H "X-Master-Key: <MASTER_KEY>"
# Copiar a key gerada → editar evaluation-service/secret-api-key.yaml → kubectl apply

# 8. evaluation-service
kubectl apply -f togglemaster-platform/k8s/evaluation-service/deployment.yaml
kubectl apply -f togglemaster-platform/k8s/evaluation-service/service.yaml

# 9. analytics-service (independente, pode subir junto)
kubectl apply -f togglemaster-platform/k8s/analytics-service/deployment.yaml
kubectl apply -f togglemaster-platform/k8s/analytics-service/service.yaml
```

### Apply completo (após preencher todos os placeholders)

```bash
kubectl apply -f togglemaster-platform/k8s/namespace.yaml
kubectl apply -f togglemaster-platform/k8s/configmap-common.yaml
kubectl apply -f togglemaster-platform/k8s/auth-service/
kubectl apply -f togglemaster-platform/k8s/flag-service/
kubectl apply -f togglemaster-platform/k8s/targeting-service/
kubectl apply -f togglemaster-platform/k8s/evaluation-service/
kubectl apply -f togglemaster-platform/k8s/analytics-service/
```

---

## Verificação

```bash
# Todos os pods no namespace
kubectl get pods -n togglemaster

# Status dos ExternalSecrets
kubectl get externalsecret -n togglemaster

# Logs de um serviço
kubectl logs -l app=auth-service -n togglemaster --tail=50

# Health via port-forward
kubectl port-forward svc/auth-service 8001:8001 -n togglemaster
curl http://localhost:8001/health

kubectl port-forward svc/flag-service 8002:8002 -n togglemaster
curl http://localhost:8002/health

kubectl port-forward svc/targeting-service 8003:8003 -n togglemaster
curl http://localhost:8003/health

kubectl port-forward svc/evaluation-service 8004:8004 -n togglemaster
curl http://localhost:8004/health

kubectl port-forward svc/analytics-service 8005:8005 -n togglemaster
curl http://localhost:8005/health

# Testar pipeline evaluation → SQS → analytics
curl -X POST http://localhost:8004/evaluate \
  -H "Content-Type: application/json" \
  -H "X-API-Key: <SERVICE_API_KEY>" \
  -d '{"flag_key": "minha-flag", "user_id": "user-123"}'

# Verificar logs do analytics (consumer SQS)
kubectl logs -l app=analytics-service -n togglemaster --tail=50 -f

# Verificar IRSA (token deve ter audience sts.amazonaws.com)
kubectl exec -it deploy/evaluation-service -n togglemaster -- \
  cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token | cut -d. -f2 | base64 -d 2>/dev/null
```

---

## O que ficou de fora desta fase

| Recurso | Motivo | Referência |
|---|---|---|
| `Ingress` ALB | Fase 2 — requer domínio/ACM | `K8S-PLATFORM-CONTEXT.md` seção Ingress |
| `HorizontalPodAutoscaler` | Fase 3 — após carga estável | `K8S-PLATFORM-CONTEXT.md` seção HPA |
| `NetworkPolicy` | Opcional lab | — |
| `PodDisruptionBudget` | Opcional lab | — |
| Jobs de migração SQL | RDS provisionado pelo Terraform; `init.sql` foi no compose local | — |

---

## Estrutura de arquivos

```
k8s/
  namespace.yaml
  configmap-common.yaml
  auth-service/
    deployment.yaml
    service.yaml
    externalsecret.yaml        ← gera Secret "auth-service-rds-secret"
    secret-master-key.yaml     ← MASTER_KEY (placeholder manual)
  flag-service/
    deployment.yaml
    service.yaml
    externalsecret.yaml        ← gera Secret "flag-service-rds-secret"
  targeting-service/
    deployment.yaml
    service.yaml
    externalsecret.yaml        ← gera Secret "targeting-service-rds-secret"
  evaluation-service/
    serviceaccount.yaml        ← IRSA annotation
    deployment.yaml
    service.yaml
    secret-api-key.yaml        ← SERVICE_API_KEY (placeholder manual)
  analytics-service/
    serviceaccount.yaml        ← IRSA annotation
    deployment.yaml
    service.yaml
  README.md                    ← este arquivo
```
