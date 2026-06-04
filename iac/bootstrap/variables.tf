variable "region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "system" {
  description = "Nome do sistema (prefixo dos recursos)."
  type        = string
  default     = "togglemaster"
}

variable "github_repository" {
  description = "Repositório <org>/<repo> autorizado a assumir a role OIDC da esteira."
  type        = string
  default     = "fiap-tech-challenge-devops/togglemaster-platform"
}

variable "create_github_oidc_provider" {
  description = "Criar o OIDC provider do GitHub. Use false se já existir na conta (usa data source)."
  type        = bool
  default     = true
}

variable "github_actions_role_name" {
  description = "Nome da IAM role assumida pela esteira via OIDC."
  type        = string
  default     = "github-actions-iac"
}
