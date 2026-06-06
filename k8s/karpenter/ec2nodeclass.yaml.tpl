# EC2NodeClass — detalhes AWS do nó. TEMPLATE: __KARPENTER_NODE_ROLE__ é
# substituído no deploy pelo nome real da role (vem do SSM, sufixo aleatório).
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  # AMI EKS-optimized AL2023 mais recente (alias resolve a versão por nós).
  amiSelectorTerms:
    - alias: al2023@latest
  # Role que os nós provisionados assumem (criada pelo módulo eks/addons).
  role: "__KARPENTER_NODE_ROLE__"
  # Descobre as subnets PRIVADAS deste cluster pelas tags existentes.
  subnetSelectorTerms:
    - tags:
        kubernetes.io/role/internal-elb: "1"
        kubernetes.io/cluster/eks-togglemaster: shared
  # Descobre o security group do cluster (node<->control-plane, node<->node).
  securityGroupSelectorTerms:
    - tags:
        "aws:eks:cluster-name": eks-togglemaster
  # maxPods alto: resolve o muro dos 17 NOS NÓS DO KARPENTER (precisa do prefix
  # delegation, que já está ligado no vpc-cni).
  kubelet:
    maxPods: 110
  # Tags aplicadas às instâncias/volumes criados (custo/rastreio).
  tags:
    Project: ToggleMaster
    ManagedBy: karpenter
