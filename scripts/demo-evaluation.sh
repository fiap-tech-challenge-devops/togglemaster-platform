#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Demo 1 — escala do evaluation-service por CPU (HPA)
#
# Gera carga HTTP EXTERNA no /evaluate, direto no DNS público do ALB (entra pelo
# Ingress, como um cliente real). O 'hey' roda num container LOCAL (docker), então
# o tráfego se origina FORA do cluster. A CPU do evaluation sobe e o HPA aumenta as
# réplicas.
#
# CONTROLE DA TAXA: use o rate limit (-q) para capar req/s independente da rapidez
# do endpoint. Taxa total ≈ CONCURRENCY × RATE (req/s). Menos req/s = menos mensagens
# na SQS (o /evaluate emite 1 evento por request), então o analytics/KEDA quase não
# reage — deixando o HPA do evaluation como protagonista.
#
# Uso:   bash scripts/demo-evaluation.sh [duração] [concorrência] [flag] [rate_qps]
# Ex.:   bash scripts/demo-evaluation.sh 120s 5 enable-new-dashboard 10   # ~50 req/s
#
# Acompanhe em OUTRO terminal:
#   kubectl get hpa evaluation-service -n togglemaster -w
#   kubectl get pods -n togglemaster -l app=evaluation-service -w
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash (Windows): não converter /bin/... em path Windows

NS=togglemaster
DURATION="${1:-120s}"               # duração da carga
CONCURRENCY="${2:-4}"               # conexões simultâneas
FLAG="${3:-enable-new-dashboard}"   # flag avaliada (criada na demo)
RATE="${4:-10}"                     # QPS POR WORKER (0 = ilimitado). Total ≈ CONCURRENCY × RATE

# DNS público do ALB (Ingress) — captura dinâmica
ALB="$(kubectl get ingress togglemaster -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
if [[ -z "$ALB" ]]; then
  echo "ERRO: não consegui obter o DNS do ALB (ingress togglemaster). O ALB já subiu?" >&2
  exit 1
fi

TARGET="http://${ALB}/evaluate?user_id=demo&flag_name=${FLAG}"

# Rate limit: -q só entra se RATE != 0. Total aproximado = CONCURRENCY × RATE.
QFLAG=""
TOTAL_RPS="ilimitado"
if [[ "$RATE" != "0" ]]; then
  QFLAG="-q $RATE"
  TOTAL_RPS="~$((CONCURRENCY * RATE)) req/s"
fi

echo ">> Demo 1 — carga EXTERNA no evaluation-service via ALB (HPA por CPU)"
echo ">> ALB=${ALB}"
echo ">> duração=${DURATION}  concorrência=${CONCURRENCY}  rate=${RATE} qps/worker  (total ${TOTAL_RPS})  flag=${FLAG}"
echo ">> acompanhe: kubectl get hpa evaluation-service -n ${NS} -w"
echo

# 'hey' via container local: o tráfego sai da sua máquina e entra pelo ALB (externo).
# shellcheck disable=SC2086  # $QFLAG precisa expandir em 2 args (-q N)
docker run --rm williamyeh/hey -z "$DURATION" -c "$CONCURRENCY" $QFLAG "$TARGET"
