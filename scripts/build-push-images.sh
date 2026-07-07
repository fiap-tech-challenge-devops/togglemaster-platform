#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Pré-passo MANUAL (fora da esteira): cria os repos ECR e faz build+push das 5
# imagens. É manual de propósito — o deploy da esteira depende das imagens já
# existirem nos repos, então não faz sentido criar o ECR dentro do apply.
#
# Padrão de nomenclatura: togglemaster/<serviço>
# Account ID e região são auto-detectados (portável entre contas).
#
# Uso:   bash scripts/build-push-images.sh [profile] [região]
# Ex.:   bash scripts/build-push-images.sh VitaoAWS us-east-1
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
export MSYS_NO_PATHCONV=1

# Roda a partir da raiz do togglemaster-platform (os serviços são irmãos: ../<svc>)
cd "$(dirname "$0")/.." || exit 1

PROFILE="${1:-}"
REGION="${2:-us-east-1}"
PROFILE_ARG=""
[ -n "$PROFILE" ] && PROFILE_ARG="--profile $PROFILE"

SERVICES="auth-service flag-service targeting-service evaluation-service analytics-service"

ACCOUNT_ID=$(aws sts get-caller-identity $PROFILE_ARG --query Account --output text)
REG="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
echo ">> Conta ${ACCOUNT_ID} / região ${REGION} / registry ${REG}"

# 1. Garante os repos (cria se não existir)
for svc in $SERVICES; do
  aws ecr describe-repositories --repository-names "togglemaster/$svc" $PROFILE_ARG --region "$REGION" >/dev/null 2>&1 \
    || { echo ">> criando repo togglemaster/$svc"; aws ecr create-repository --repository-name "togglemaster/$svc" $PROFILE_ARG --region "$REGION" >/dev/null; }
done

# 2. Login no ECR
aws ecr get-login-password $PROFILE_ARG --region "$REGION" | docker login --username AWS --password-stdin "$REG"

# 3. Build + push (platform amd64 — nós EKS são x86_64)
for svc in $SERVICES; do
  echo ">> build+push $svc"
  docker build --platform linux/amd64 -t "$REG/togglemaster/$svc:latest" "../$svc"
  docker push "$REG/togglemaster/$svc:latest"
done

echo ">> Pronto — 5 imagens em ${REG}/togglemaster/*:latest"
