output "state_bucket" {
  description = "Bucket S3 do state remoto (use em -backend-config=bucket=...)."
  value       = aws_s3_bucket.tfstate.id
}

output "lock_table" {
  description = "Tabela DynamoDB de lock (use em -backend-config=dynamodb_table=...)."
  value       = aws_dynamodb_table.tflock.id
}

output "github_actions_role_arn" {
  description = "ARN da role OIDC — configure no secret AWS_OIDC_ROLE_ARN do repositório."
  value       = aws_iam_role.github_actions.arn
}

output "backend_config_hint" {
  description = "Argumentos de -backend-config para os stages infra/addons."
  value       = "-backend-config=bucket=${aws_s3_bucket.tfstate.id} -backend-config=region=${var.region} -backend-config=dynamodb_table=${aws_dynamodb_table.tflock.id}"
}
