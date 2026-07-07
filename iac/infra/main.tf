# Account ID da conta onde o Terraform está rodando — usado para montar os ARNs
# de admin do EKS sem hardcodar a conta (portável na migração).
data "aws_caller_identity" "current" {}

locals {
  cluster_name = "eks-${var.system}"

  # ARNs dos usuários admin, montados com o account atual (auto-detectado).
  admin_iam_arns = [
    for u in var.admin_iam_usernames : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${u}"
  ]

  tags = {
    Project = "ToggleMaster"
    System  = var.system
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

# ── EKS (node principal ON_DEMAND; burst em SPOT via Karpenter) ───────────────
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

  # Node group principal ON_DEMAND (baseline estável). Fixo em 1 nó dimensionado
  # para o sistema em repouso; o burst dos testes de carga vai para o Karpenter (SPOT).
  # Sem taint, para os pods de sistema agendarem normalmente neste nó.
  node_groups = {
    baseline = {
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"
      desired_size   = var.node_desired_size
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      labels = {
        role = "baseline"
      }
    }
  }

  # Prefix delegation no VPC-CNI: a ENI aloca blocos /28 de IPs. Beneficia os nós do
  # KARPENTER, que setam max-pods=110 explicitamente (k8s/karpenter/ec2nodeclass.yaml.tpl).
  # O managed node group NÃO usa esse override (o módulo não expõe), então o nó principal
  # usa o max-pods NATIVO do tipo: t3.large = 35 (suficiente p/ os ~22 pods do baseline).
  cluster_addons = {
    coredns    = {}
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

  name                = "rds-${var.system}-${each.key}"
  security_group_name = "rds-sg-${var.system}-${each.key}" # rds-sg-togglemaster-<svc>
  engine              = "postgres"
  engine_version      = var.rds_engine_version
  instance_class      = var.rds_instance_class

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

  name                = "redis-${var.system}"
  security_group_name = "redis-sg-${var.system}" # redis-sg-togglemaster
  engine              = "redis"
  engine_version      = var.redis_engine_version
  node_type           = var.redis_node_type

  num_cache_clusters = 1

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_cidr_blocks = [var.vpc_cidr]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false # evaluation-service usa redis:// (sem TLS)
  snapshot_retention_limit   = 0     # cache puro (lab)

  tags = local.tags
}

# ── SQS (evaluation-events) ───────────────────────────────────────────────────
module "sqs" {
  source = "github.com/vitorfprado/terraform-aws-modules//sqs?ref=main"

  name                      = "${var.system}-evaluation-events"
  receive_wait_time_seconds = 20 # long polling (igual ao analytics-service)
  # O desafio pede só 1 fila SQS Standard — DLQ não é requisito. (Default do módulo é true.)
  create_dlq = false

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
  for_each = toset(local.admin_iam_arns)

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(local.admin_iam_arns)

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
