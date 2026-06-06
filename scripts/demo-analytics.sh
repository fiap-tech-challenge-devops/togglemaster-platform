#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Demo 2 — escala do analytics-service por profundidade de fila (KEDA)
#
# Sobe um pod efêmero (aws-cli) que injeta mensagens na fila SQS usando o IRSA do
# service account "evaluation-service" (sqs:SendMessage) — SEM credencial estática.
# A fila enche, o KEDA detecta a profundidade e escala o analytics. Pod --rm no fim.
#
# Uso:   bash scripts/demo-analytics.sh [quantidade]
# Ex.:   bash scripts/demo-analytics.sh 4000
#
# Acompanhe em OUTRO terminal:
#   kubectl get scaledobject,hpa -n togglemaster -w
#   kubectl get pods -n togglemaster -l app=analytics-service -w
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash (Windows): não converter paths

NS=togglemaster
COUNT="${1:-4000}"        # quantidade de mensagens (default 4000)
QURL="https://sqs.us-east-1.amazonaws.com/650687537445/togglemaster-evaluation-events"

echo ">> Demo 2 — injetando ${COUNT} mensagens na SQS (KEDA por fila)"
echo ">> via pod efêmero com IRSA do SA evaluation-service (sem credencial)"
echo ">> acompanhe: kubectl get scaledobject,hpa -n ${NS} -w"
echo

# O loop roda DENTRO do pod (Linux). QURL/COUNT chegam como env; $i é do pod.
# 60 envios em paralelo por vez (wait) para injetar rápido sem estourar.
kubectl run sqs-load --rm -i --restart=Never -n "$NS" \
  --image=amazon/aws-cli \
  --env="QURL=$QURL" --env="COUNT=$COUNT" \
  --overrides='{"spec":{"serviceAccountName":"evaluation-service"}}' \
  --command -- /bin/bash -c 'for i in $(seq 1 "$COUNT"); do aws sqs send-message --queue-url "$QURL" --message-body "{\"user_id\":\"load-$i\",\"flag_name\":\"new-checkout\",\"result\":true,\"timestamp\":\"2026-06-06T13:00:00Z\"}" >/dev/null & [ $((i % 60)) -eq 0 ] && wait; done; wait; echo "$COUNT mensagens enviadas"'
