# ── KEDA — IRSA do keda-operator ──────────────────────────────────────────────
# A INSTALAÇÃO do KEDA agora é feita pelo módulo eks/addons (enable_keda, ver main.tf).
# Aqui fica apenas a IRSA específica deste uso: o analytics-service escala pela
# PROFUNDIDADE DA FILA SQS (não por CPU). Quem consulta a fila para decidir a escala
# é o keda-operator — por isso ele precisa da própria role IRSA com
# sqs:GetQueueAttributes, separada da role dos pods do analytics (que têm
# Receive/Delete para PROCESSAR as mensagens). A anotação dessa role no SA do operator
# é injetada via keda_helm_values na chamada do módulo (main.tf).

# Resolve o ARN da fila criada no stage infra (sem acoplar via remote state).
data "aws_sqs_queue" "evaluation_events" {
  name = "${var.system}-evaluation-events"
}

# Policy mínima: só LER a profundidade da fila.
data "aws_iam_policy_document" "keda" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:GetQueueAttributes"]
    resources = [data.aws_sqs_queue.evaluation_events.arn]
  }
}

# Role IRSA para o SA keda-operator (namespace keda).
module "irsa_keda" {
  source = "github.com/vitorfprado/terraform-aws-modules//iam-irsa?ref=main"

  name              = "role-eks-${var.system}-keda"
  oidc_provider_arn = local.oidc_provider_arn
  oidc_provider_url = local.oidc_provider_url

  namespace        = "keda"
  service_accounts = ["keda-operator"]

  inline_policies = { sqs = data.aws_iam_policy_document.keda.json }

  tags = local.tags
}
