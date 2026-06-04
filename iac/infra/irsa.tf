# ── IRSA das aplicações ───────────────────────────────────────────────────────
# Namespace/SA batem com os manifestos em k8s/ (namespace togglemaster).
# create_ssm_parameter publica o ARN em /irsa/<name>/role-arn para os manifestos.

# evaluation-service → produz eventos na fila SQS
data "aws_iam_policy_document" "evaluation" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
    resources = [module.sqs.queue_arn]
  }
}

module "irsa_evaluation" {
  source = "github.com/vitorfprado/terraform-aws-modules//iam-irsa?ref=main"

  name              = "role-eks-${var.system}-evaluation"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  namespace        = "togglemaster"
  service_accounts = ["evaluation-service"]

  inline_policies      = { app = data.aws_iam_policy_document.evaluation.json }
  create_ssm_parameter = true

  tags = local.tags
}

# analytics-service → consome a fila SQS e grava no DynamoDB
data "aws_iam_policy_document" "analytics" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
    resources = [module.sqs.queue_arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DescribeTable"]
    resources = [module.dynamodb.table_arn]
  }
}

module "irsa_analytics" {
  source = "github.com/vitorfprado/terraform-aws-modules//iam-irsa?ref=main"

  name              = "role-eks-${var.system}-analytics"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  namespace        = "togglemaster"
  service_accounts = ["analytics-service"]

  inline_policies      = { app = data.aws_iam_policy_document.analytics.json }
  create_ssm_parameter = true

  tags = local.tags
}
