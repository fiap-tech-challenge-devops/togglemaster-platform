#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# kubectl apply com substituição do placeholder ${AWS_ACCOUNT_ID} — uso LOCAL.
#
# Os manifests em k8s/ usam ${AWS_ACCOUNT_ID} em vez do ID hardcoded, para serem
# portáveis entre contas. O pipeline substitui isso automaticamente; para aplicar
# manualmente, use este helper (auto-detecta a conta via STS).
#
# Uso:   bash scripts/kapply.sh <arquivo.yaml | diretório>
# Ex.:   bash scripts/kapply.sh k8s/analytics-service/scaledobject.yaml
#        bash scripts/kapply.sh k8s/
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
export MSYS_NO_PATHCONV=1

TARGET="${1:?uso: bash scripts/kapply.sh <arquivo.yaml|dir>}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

apply_one() { sed "s|[$]{AWS_ACCOUNT_ID}|${ACCOUNT_ID}|g" "$1"; echo "---"; }

if [[ -d "$TARGET" ]]; then
  find "$TARGET" -name '*.yaml' -print0 \
    | while IFS= read -r -d '' f; do apply_one "$f"; done | kubectl apply -f -
else
  apply_one "$TARGET" | kubectl apply -f -
fi
