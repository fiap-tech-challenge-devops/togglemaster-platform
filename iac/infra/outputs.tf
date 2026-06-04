# ── VPC ───────────────────────────────────────────────────────────────────────
output "vpc_id" {
  description = "ID da VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas"
  value       = module.vpc.private_subnet_ids
}

# ── EKS ───────────────────────────────────────────────────────────────────────
output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint da API do EKS"
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "ARN do OIDC provider (para IRSA — usado pelos gaps: evaluation/analytics)"
  value       = module.eks.oidc_provider_arn
}

output "update_kubeconfig_command" {
  description = "Comando para configurar o kubectl após o apply"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

# ── RDS ───────────────────────────────────────────────────────────────────────
output "rds_endpoints" {
  description = "Endpoints dos 3 RDS (host:port)"
  value       = { for k, m in module.rds : k => m.db_instance_endpoint }
}

output "rds_secret_arns" {
  description = "ARNs dos secrets togglemaster/rds/<svc> (com connection_string, consumidos pelo External Secrets)"
  value       = { for k, m in module.rds_secret : k => m.secret_arn }
}

output "rds_secret_names" {
  description = "Nomes dos secrets (key do remoteRef nos ExternalSecrets)"
  value       = { for k, m in module.rds_secret : k => m.secret_name }
}

# ── ElastiCache Redis ─────────────────────────────────────────────────────────
output "redis_url" {
  description = "REDIS_URL para o evaluation-service (redis://host:6379/0)"
  value       = "redis://${module.redis.primary_endpoint_address}:${module.redis.port}/0"
}

# ── SQS ───────────────────────────────────────────────────────────────────────
output "sqs_queue_url" {
  description = "URL da fila SQS"
  value       = module.sqs.queue_url
}

output "sqs_queue_arn" {
  description = "ARN da fila SQS"
  value       = module.sqs.queue_arn
}

# ── DynamoDB ──────────────────────────────────────────────────────────────────
output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB"
  value       = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  description = "ARN da tabela DynamoDB"
  value       = module.dynamodb.table_arn
}

# ── IRSA (apps) ───────────────────────────────────────────────────────────────
output "irsa_evaluation_role_arn" {
  description = "ARN da IRSA do evaluation-service (annotation eks.amazonaws.com/role-arn)"
  value       = module.irsa_evaluation.role_arn
}

output "irsa_analytics_role_arn" {
  description = "ARN da IRSA do analytics-service (annotation eks.amazonaws.com/role-arn)"
  value       = module.irsa_analytics.role_arn
}

output "irsa_ssm_parameters" {
  description = "Parâmetros SSM com os ARNs das roles IRSA (consumidos pelos manifestos)"
  value = {
    evaluation = module.irsa_evaluation.ssm_parameter_name
    analytics  = module.irsa_analytics.ssm_parameter_name
  }
}
