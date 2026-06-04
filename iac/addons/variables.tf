variable "region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "system" {
  description = "Nome do sistema (prefixo dos parâmetros SSM publicados pelo stage infra)."
  type        = string
  default     = "togglemaster"
}

variable "external_secrets_namespace" {
  description = "Namespace do External Secrets Operator."
  type        = string
  default     = "external-secrets"
}
