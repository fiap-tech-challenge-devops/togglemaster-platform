#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Demo 1 — escala do evaluation-service por CPU (HPA)
#
# Gera carga HTTP EXTERNA no /evaluate, direto no DNS público do ALB (entra pelo
# Ingress, como um cliente real). O 'hey' roda num container LOCAL (docker), então
# o tráfego se origina FORA do cluster. A CPU do evaluation sobe e o HPA aumenta as
# réplicas.
#
# Uso:   bash scripts/demo-evaluation.sh [duração] [concorrência] [flag]
# Ex.:   bash scripts/demo-evaluation.sh 120s 100 enable-new-dashboard
#
# Acompanhe em OUTRO terminal:
#   kubectl get hpa evaluation-service -n togglemaster -w
#   kubectl get pods -n togglemaster -l app=evaluation-service -w
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash (Windows): não converter /bin/... em path Windows

NS=togglemaster
DURATION="${1:-60s}"           # duração da carga (default 60s — pico curto p/ HPA)
CONCURRENCY="${2:-150}"        # conexões simultâneas (default 150)
FLAG="${3:-enable-new-dashboard}"   # flag avaliada (default enable-new-dashboard, criada na demo)

# DNS público do ALB (Ingress) — captura dinâmica
ALB="$(kubectl get ingress togglemaster -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
if [[ -z "$ALB" ]]; then
  echo "ERRO: não consegui obter o DNS do ALB (ingress togglemaster). O ALB já subiu?" >&2
  exit 1
fi

TARGET="http://${ALB}/evaluate?user_id=demo&flag_name=${FLAG}"

echo ">> Demo 1 — carga EXTERNA no evaluation-service via ALB (HPA por CPU)"
echo ">> ALB=${ALB}"
echo ">> duração=${DURATION}  concorrência=${CONCURRENCY}  flag=${FLAG}"
echo ">> acompanhe: kubectl get hpa evaluation-service -n ${NS} -w"
echo

# 'hey' via container local: o tráfego sai da sua máquina e entra pelo ALB (externo).
docker run --rm williamyeh/hey -z "$DURATION" -c "$CONCURRENCY" "$TARGET"
