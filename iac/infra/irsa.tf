# ── IRSA das aplicações (role ÚNICA do namespace togglemaster) ────────────────
# Lab: consolidamos evaluation + analytics numa única role compartilhada por todos
# os SAs do namespace togglemaster (service_accounts = ["*"]). A policy reúne o que
# os dois precisam: produzir/consumir na fila SQS e gravar no DynamoDB.
#
# A segmentação por microsserviço (uma role <-> um SA, com policies assimétricas de
# menor-privilégio) fica registrada como melhoria para produção — ver
# ai/autorizacoes-iam-rbac.md. Namespace/SA batem com os manifestos em k8s/.
# create_ssm_parameter publica o ARN em /irsa/<name>/role-arn para os manifestos.
data "aws_iam_policy_document" "apps" {
  # SQS: evaluation PRODUZ (SendMessage); analytics CONSOME (Receive/Delete).
  statement {
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]
    resources = [module.sqs.queue_arn]
  }

  # DynamoDB: analytics grava os eventos processados.
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DescribeTable"]
    resources = [module.dynamodb.table_arn]
  }
}

module "irsa_apps" {
  source = "github.com/vitorfprado/terraform-aws-modules//iam-irsa?ref=main"

  name              = "role-eks-${var.system}-apps"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  namespace        = "togglemaster"
  service_accounts = ["*"] # qualquer SA do namespace togglemaster assume esta role

  inline_policies      = { app = data.aws_iam_policy_document.apps.json }
  create_ssm_parameter = true

  tags = local.tags
}
