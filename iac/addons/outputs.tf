output "eso_role_arn" {
  description = "ARN da IRSA do External Secrets Operator."
  value       = module.irsa_eso.role_arn
}

output "lbc_role_arn" {
  description = "ARN da IRSA do AWS Load Balancer Controller."
  value       = module.addons.aws_load_balancer_controller_iam_role_arn
}

output "cluster_secret_store" {
  description = "Nome da ClusterSecretStore criada para o External Secrets."
  value       = "aws-secrets-manager"
}
