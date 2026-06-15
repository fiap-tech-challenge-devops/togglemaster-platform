variable "region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "admin_iam_arns" {
  description = "Lista de ARNs IAM (usuários/roles) que recebem acesso cluster-admin no EKS"
  type        = list(string)
  default     = ["arn:aws:iam::650687537445:user/vitor.prado"]
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

# ── Node group principal (ON_DEMAND, baseline fixo) ───────────────────────────
# Nó estável (não-SPOT) dimensionado para rodar TODO o sistema em repouso (~22 pods,
# ~1.1 vCPU). O burst dos testes de carga vai para o Karpenter (SPOT) — ver
# k8s/karpenter/nodepool.yaml. Por isso o managed node group fica fixo em 1 nó.

variable "node_instance_types" {
  description = "Tipo de instância do node principal (on-demand). t3.large: 35 maxPods (cabe os ~22 pods do baseline) / 2 vCPU / 8 GB"
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_desired_size" {
  description = "Nós desejados no baseline (fixo em 1 — o burst é responsabilidade do Karpenter)"
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Mínimo de nós do baseline (1 = sempre há o nó principal; ASG recria se ele cair)"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Máximo de nós do baseline (1 = o managed node group NÃO escala; quem escala é o Karpenter SPOT)"
  type        = number
  default     = 1
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
