# ── Handoff stage 1 → stage 2 via SSM Parameter Store ─────────────────────────
# O stage de addons lê estes parâmetros (sem terraform_remote_state) para
# configurar os providers k8s/helm e o módulo eks/addons.

locals {
  ssm_prefix = "/${var.system}/iac"
}

resource "aws_ssm_parameter" "cluster_name" {
  name  = "${local.ssm_prefix}/cluster-name"
  type  = "String"
  value = module.eks.cluster_name
  tags  = local.tags
}

resource "aws_ssm_parameter" "oidc_provider_arn" {
  name  = "${local.ssm_prefix}/oidc-provider-arn"
  type  = "String"
  value = module.eks.oidc_provider_arn
  tags  = local.tags
}

resource "aws_ssm_parameter" "oidc_provider_url" {
  name  = "${local.ssm_prefix}/oidc-provider-url"
  type  = "String"
  value = module.eks.oidc_provider_url
  tags  = local.tags
}

resource "aws_ssm_parameter" "vpc_id" {
  name  = "${local.ssm_prefix}/vpc-id"
  type  = "String"
  value = module.vpc.vpc_id
  tags  = local.tags
}

# REDIS_URL completo — injetado no ConfigMap evaluation-service-config pelo stage de deploy
resource "aws_ssm_parameter" "redis_url" {
  name  = "${local.ssm_prefix}/redis-url"
  type  = "String"
  value = "redis://${module.redis.primary_endpoint_address}:${module.redis.port}/0"
  tags  = local.tags
}
