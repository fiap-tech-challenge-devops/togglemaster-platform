data "aws_ssm_parameter" "oidc_provider_arn" {
  name = "/${var.system}/iac/oidc-provider-arn"
}

data "aws_ssm_parameter" "oidc_provider_url" {
  name = "/${var.system}/iac/oidc-provider-url"
}

data "aws_ssm_parameter" "vpc_id" {
  name = "/${var.system}/iac/vpc-id"
}

locals {
  oidc_provider_arn = nonsensitive(data.aws_ssm_parameter.oidc_provider_arn.value)
  oidc_provider_url = nonsensitive(data.aws_ssm_parameter.oidc_provider_url.value)
  vpc_id            = nonsensitive(data.aws_ssm_parameter.vpc_id.value)
  cluster_name      = data.aws_eks_cluster.this.name

  tags = {
    Project   = "ToggleMaster"
    System    = var.system
    ManagedBy = "terraform"
    Stack     = "iac-addons"
  }
}

# ── IRSA do External Secrets Operator ─────────────────────────────────────────
# O módulo eks/addons instala o ESO mas NÃO wira IRSA para ele — completamos aqui.
data "aws_iam_policy_document" "eso" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
    ]
    resources = ["*"]
  }
}

module "irsa_eso" {
  source = "github.com/vitorfprado/terraform-aws-modules//iam-irsa?ref=main"

  name              = "role-eks-${var.system}-external-secrets"
  oidc_provider_arn = local.oidc_provider_arn
  oidc_provider_url = local.oidc_provider_url

  namespace        = var.external_secrets_namespace
  service_accounts = ["external-secrets"]

  inline_policies = { secretsmanager = data.aws_iam_policy_document.eso.json }

  tags = local.tags
}

# ── Addons via Helm (metrics-server, ALB controller, External Secrets) ────────
module "addons" {
  source = "github.com/vitorfprado/terraform-aws-modules//eks/addons?ref=main"

  cluster_name      = local.cluster_name
  oidc_provider_arn = local.oidc_provider_arn
  oidc_provider_url = local.oidc_provider_url
  vpc_id            = local.vpc_id
  region            = var.region

  enable_metrics_server               = true
  enable_aws_load_balancer_controller = true
  enable_external_secrets             = true
  external_secrets_namespace          = var.external_secrets_namespace

  # Karpenter: o módulo cria controller (IRSA), IAM role dos nós, access entry,
  # fila SQS de interrupção + EventBridge. As CRDs NodePool/EC2NodeClass ficam em
  # k8s/karpenter/ (aplicadas no deploy).
  # Chart 1.3.3: o default do módulo (1.1.1) NÃO suporta k8s 1.32 (controller dá
  # panic "not compatible with K8s version 1.32"). Karpenter >= 1.2 é necessário.
  enable_karpenter        = true
  karpenter_chart_version = "1.3.3"

  # Desabilita o service mutator webhook do ALB controller. Esse webhook
  # intercepta TODO Service do cluster e, antes dos pods do controller ficarem
  # prontos, quebra a criação de Services de outros charts (ex.: ESO) com
  # "no endpoints available for service aws-load-balancer-webhook-service".
  # Só usamos Ingress (ALB), nunca Service type=LoadBalancer — webhook é dispensável.
  aws_load_balancer_controller_helm_values = [
    yamlencode({
      enableServiceMutatorWebhook = false
    })
  ]

  # O módulo não anota a SA do ESO com a role IRSA — injetamos via helm values.
  external_secrets_helm_values = [
    yamlencode({
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.irsa_eso.role_arn
        }
      }
    })
  ]

  tags = local.tags
}

# A ClusterSecretStore (ESO → Secrets Manager) é aplicada no stage de DEPLOY
# (k8s/cluster-secret-store.yaml) — via kubectl, com a CRD do ESO já estabelecida.
# Criá-la aqui pelo provider kubectl falhava: o discovery da API era cacheado
# antes da CRD existir ("ClusterSecretStore isn't valid for cluster").
