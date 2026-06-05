variable "region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "system" {
  description = "Nome do sistema — base para o padrão <tipo>-<sistema>"
  type        = string
  default     = "togglemaster"
}

variable "cluster_version" {
  description = "Versão do Kubernetes do cluster EKS"
  type        = string
  default     = "1.32"
}

variable "vpc_cidr" {
  description = "CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas (uma por AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas (uma por AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# ── Node group SPOT (mínimo necessário) ───────────────────────────────────────

variable "node_instance_types" {
  description = "Tipos de instância do node group SPOT (diversificação melhora disponibilidade de SPOT)"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "node_desired_size" {
  description = "Quantidade desejada de nós"
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Mínimo de nós"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Máximo de nós"
  type        = number
  default     = 2
}

# ── RDS ───────────────────────────────────────────────────────────────────────

variable "rds_engine_version" {
  description = "Versão do PostgreSQL nos RDS"
  type        = string
  default     = "16"
}

variable "rds_instance_class" {
  description = "Classe de instância dos RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "Armazenamento (GB) por instância RDS"
  type        = number
  default     = 20
}

# ── ElastiCache Redis ─────────────────────────────────────────────────────────

variable "redis_engine_version" {
  description = "Versão da engine Redis"
  type        = string
  default     = "7.1"
}

variable "redis_node_type" {
  description = "Tipo de nó do ElastiCache"
  type        = string
  default     = "cache.t4g.micro"
}
