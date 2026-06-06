#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Demo 1 — escala do evaluation-service por CPU (HPA)
#
# Sobe um pod efêmero "hey" que gera carga HTTP no /evaluate (service interno).
# A CPU do evaluation sobe e o HPA aumenta as réplicas. O pod se autodestrói (--rm).
#
# Uso:   bash scripts/demo-evaluation.sh [duração] [concorrência]
# Ex.:   bash scripts/demo-evaluation.sh 120s 100
#
# Acompanhe em OUTRO terminal:
#   kubectl get hpa evaluation-service -n togglemaster -w
#   kubectl get pods -n togglemaster -l app=evaluation-service -w
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash (Windows): não converter /bin/... em path Windows

NS=togglemaster
DURATION="${1:-120s}"     # duração da carga (default 120s)
CONCURRENCY="${2:-100}"   # conexões simultâneas (default 100)
TARGET="http://evaluation-service:8004/evaluate?user_id=demo&flag_name=new-checkout"

echo ">> Demo 1 — carga no evaluation-service (HPA por CPU)"
echo ">> duração=${DURATION}  concorrência=${CONCURRENCY}"
echo ">> acompanhe: kubectl get hpa evaluation-service -n ${NS} -w"
echo

kubectl run hey-load --rm -i --restart=Never -n "$NS" \
  --image=williamyeh/hey -- \
  -z "$DURATION" -c "$CONCURRENCY" "$TARGET"
