# Publica o nome da IAM role dos nós do Karpenter (gerada com sufixo aleatório pelo
# módulo) para o stage de deploy substituir no EC2NodeClass (k8s/karpenter/ec2nodeclass.yaml.tpl).
# Mesma estratégia de handoff via SSM usada para REDIS_URL etc.
resource "aws_ssm_parameter" "karpenter_node_role" {
  name  = "/${var.system}/iac/karpenter-node-role"
  type  = "String"
  value = module.addons.karpenter_node_iam_role_name

  tags = local.tags
}
