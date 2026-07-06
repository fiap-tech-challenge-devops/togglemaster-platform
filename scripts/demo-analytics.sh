#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Demo 2 — escala do analytics-service por profundidade de fila (KEDA)
#
# Sobe um pod efêmero (aws-cli) que injeta mensagens na fila SQS usando o IRSA do
# service account "evaluation-service" (sqs:SendMessage) — SEM credencial estática.
# A fila enche, o KEDA detecta a profundidade e escala o analytics. Pod --rm no fim.
#
# Injeção em LOTE: usa `send-message-batch` (10 msgs por chamada), então são
# COUNT/10 invocações do aws em vez de COUNT — muito mais rápido (o cold-start do
# aws CLI era o gargalo). ~20 lotes em paralelo por vez.
#
# Uso:   bash scripts/demo-analytics.sh [quantidade]
# Ex.:   bash scripts/demo-analytics.sh 2000
#
# Acompanhe em OUTRO terminal:
#   kubectl get scaledobject,hpa -n togglemaster -w
#   kubectl get pods -n togglemaster -l app=analytics-service -w
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash (Windows): não converter paths

NS=togglemaster
COUNT="${1:-2000}"        # quantidade de mensagens (default 2000)
QURL="https://sqs.us-east-1.amazonaws.com/650687537445/togglemaster-evaluation-events"

echo ">> Demo 2 — injetando ${COUNT} mensagens na SQS em LOTE (KEDA por fila)"
echo ">> via pod efêmero com IRSA do SA evaluation-service (sem credencial)"
echo ">> acompanhe: kubectl get scaledobject,hpa -n ${NS} -w"
echo

# Idempotência: remove um pod órfão de uma execução anterior interrompida (o --rm
# não limpa se você der Ctrl+C), senão o kubectl run falha com "already exists".
kubectl delete pod sqs-load -n "$NS" --ignore-not-found --wait=true >/dev/null 2>&1 || true

# O loop roda DENTRO do pod (Linux). QURL/COUNT chegam como env; $i/$j são do pod.
# Cada iteração monta um lote de até 10 entradas e envia com send-message-batch.
# Os Ids do lote precisam ser únicos por request (usamos o índice global).
kubectl run sqs-load --rm -i --restart=Never -n "$NS" \
  --image=amazon/aws-cli \
  --env="QURL=$QURL" --env="COUNT=$COUNT" \
  --overrides='{"spec":{"serviceAccountName":"evaluation-service"}}' \
  --command -- /bin/bash -c '
    for i in $(seq 1 10 "$COUNT"); do
      entries="["; first=1
      for j in $(seq "$i" $((i+9))); do
        [ "$j" -gt "$COUNT" ] && break
        [ "$first" -eq 0 ] && entries="$entries,"
        entries="$entries{\"Id\":\"$j\",\"MessageBody\":\"{\\\"user_id\\\":\\\"load-$j\\\",\\\"flag_name\\\":\\\"enable-new-dashboard\\\",\\\"result\\\":true,\\\"timestamp\\\":\\\"2026-07-06T13:00:00Z\\\"}\"}"
        first=0
      done
      entries="$entries]"
      aws sqs send-message-batch --queue-url "$QURL" --entries "$entries" >/dev/null &
      [ $(( (i/10) % 20 )) -eq 0 ] && wait
    done
    wait
    echo "$COUNT mensagens enviadas"'
