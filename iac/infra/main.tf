locals {
  cluster_name = "eks-${var.system}"

  tags = {
    Project   = "ToggleMaster"
    System    = var.system    
  }

  # 3 RDS PostgreSQL independentes — db_name/username são as strings exatas que as apps usam
  rds_instances = {
    auth      = { db_name = "auth_db", username = "auth_user" }
    flags     = { db_name = "flags_db", username = "flags_user" }
    targeting = { db_name = "targeting_db", username = "targeting_user" }
  }
}

# ── VPC ───────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "github.com/vitorfprado/terraform-aws-modules//vpc?ref=main"

  name       = var.system
  cidr_block = var.vpc_cidr

  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  enable_nat_gateway = true
  single_nat_gateway = true # 1 NAT = menor custo (lab)

  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  tags = local.tags
}

# ── EKS (node group SPOT) ─────────────────────────────────────────────────────
module "eks" {
  source = "github.com/vitorfprado/terraform-aws-modules//eks?ref=main"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  endpoint_private_access = true
  endpoint_public_access  = true

  enable_irsa    = true
  create_kms_key = true

  # Único node group, todo SPOT (sem taint para os pods de sistema agendarem normalmente)
  node_groups = {
    spot = {
      instance_types = var.node_instance_types
      capacity_type  = "SPOT"
      desired_size   = var.node_desired_size
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      labels = {
        role = "spot"
      }
    }
  }

  # Prefix delegation: aumenta max-pods de 17 → ~110 no t3.medium.
  # AL2023 EKS-optimized AMI calcula o max-pods automaticamente ao bootstap.
  cluster_addons = {
    coredns = {}
    kube-proxy = {}
    vpc-cni = {
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    eks-pod-identity-agent = {}
  }

  enable_ebs_csi_driver = false # não usamos PVCs; desabilita 3 pods de sistema

  tags = local.tags
}

# ── RDS PostgreSQL × 3 ────────────────────────────────────────────────────────
module "rds" {
  source   = "github.com/vitorfprado/terraform-aws-modules//rds?ref=main"
  for_each = local.rds_instances

  name           = "rds-${var.system}-${each.key}"
  engine         = "postgres"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  allocated_storage = var.rds_allocated_storage
  storage_type      = "gp3"

  db_name  = each.value.db_name
  username = each.value.username
  # Senha gerada pelo Terraform (não AWS-managed) para montar a connection_string
  # de nome fixo no Secrets Manager (ver secrets.tf).
  manage_master_user_password = false
  password                    = random_password.rds[each.key].result

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  # Libera Postgres (5432) para todo o CIDR da VPC — os pods recebem IP desse range
  # via VPC-CNI. Evita o gap do módulo RDS com SG computado (ver relatório de gaps).
  allowed_cidr_blocks = [var.vpc_cidr]

  # Lab / custo mínimo
  multi_az                = false
  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = local.tags
}

# ── ElastiCache Redis (evaluation-service) ────────────────────────────────────
module "redis" {
  source = "github.com/vitorfprado/terraform-aws-modules//elasticache?ref=main"

  name           = "redis-${var.system}"
  engine         = "redis"
  engine_version = var.redis_engine_version
  node_type      = var.redis_node_type

  num_cache_clusters = 1

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_cidr_blocks = [var.vpc_cidr]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false # evaluation-service usa redis:// (sem TLS)
  snapshot_retention_limit   = 0     # cache puro (lab)

  tags = local.tags
}

# ── SQS (evaluation-events + DLQ) ─────────────────────────────────────────────
module "sqs" {
  source = "github.com/vitorfprado/terraform-aws-modules//sqs?ref=main"

  name                      = "${var.system}-evaluation-events"
  receive_wait_time_seconds = 20 # long polling (igual ao analytics-service)
  create_dlq                = true

  tags = local.tags
}

# ── DynamoDB (analytics) ──────────────────────────────────────────────────────
module "dynamodb" {
  source = "github.com/vitorfprado/terraform-aws-modules//dynamodb?ref=main"

  name         = "ToggleMasterAnalytics"
  hash_key     = "event_id"
  billing_mode = "PAY_PER_REQUEST"

  attributes = [
    { name = "event_id", type = "S" }
  ]

  tags = local.tags
}

# ── EKS access entries (admin local) ─────────────────────────────────────────
resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_iam_arns)

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.admin_iam_arns)

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
