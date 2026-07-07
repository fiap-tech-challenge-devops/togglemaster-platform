#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Demo 2 — escala do analytics-service por profundidade de fila (KEDA)
#
# Sobe um pod efêmero (aws-cli) que injeta mensagens na fila SQS usando o IRSA do
# service account "evaluation-service" (sqs:SendMessage) — SEM credencial estática.
# A fila enche, o KEDA detecta a profundidade e escala o analytics. Pod --rm no fim.
#
# Injeção em RODADAS: cada rodada envia BATCH mensagens, disparando BATCH/10
# send-message-batch em paralelo (o SQS limita cada chamada a 10 mensagens). Ex.:
# BATCH=50 => 5 sub-lotes de 10 por rodada. Aguarda a rodada terminar antes da próxima.
#
# Uso:   bash scripts/demo-analytics.sh [quantidade] [batch]
# Ex.:   bash scripts/demo-analytics.sh 2000 50
#
# Acompanhe em OUTRO terminal:
#   kubectl get scaledobject,hpa -n togglemaster -w
#   kubectl get pods -n togglemaster -l app=analytics-service -w
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash (Windows): não converter paths

NS=togglemaster
COUNT="${1:-500}"        # quantidade total de mensagens (default 2000)
BATCH="${2:-50}"          # mensagens por rodada (múltiplo de 10; SQS envia 10/chamada)
# URL da fila auto-detectada (conta + região) — portável entre contas.
QURL="$(aws sqs get-queue-url --queue-name togglemaster-evaluation-events --query QueueUrl --output text)"

echo ">> Demo 2 — injetando ${COUNT} mensagens na SQS (rodadas de ${BATCH}) — KEDA por fila"
echo ">> via pod efêmero com IRSA do SA evaluation-service (sem credencial)"
echo ">> acompanhe: kubectl get scaledobject,hpa -n ${NS} -w"
echo

# Idempotência: remove pod órfão de uma execução interrompida (o --rm não limpa no Ctrl+C).
kubectl delete pod sqs-load -n "$NS" --ignore-not-found --wait=true >/dev/null 2>&1 || true

# O loop roda DENTRO do pod (Linux). QURL/COUNT/BATCH chegam como env.
# Rodada externa (passo BATCH) → sub-lotes de 10 em paralelo → wait ao fim da rodada.
kubectl run sqs-load --rm -i --restart=Never -n "$NS" \
  --image=amazon/aws-cli \
  --env="QURL=$QURL" --env="COUNT=$COUNT" --env="BATCH=$BATCH" \
  --overrides='{"spec":{"serviceAccountName":"evaluation-service"}}' \
  --command -- /bin/bash -c '
    for i in $(seq 1 "$BATCH" "$COUNT"); do
      for k in $(seq "$i" 10 $((i+BATCH-1))); do
        [ "$k" -gt "$COUNT" ] && break
        entries="["; first=1
        for j in $(seq "$k" $((k+9))); do
          [ "$j" -gt "$COUNT" ] && break
          [ "$first" -eq 0 ] && entries="$entries,"
          entries="$entries{\"Id\":\"$j\",\"MessageBody\":\"{\\\"user_id\\\":\\\"load-$j\\\",\\\"flag_name\\\":\\\"enable-new-dashboard\\\",\\\"result\\\":true,\\\"timestamp\\\":\\\"2026-07-06T13:00:00Z\\\"}\"}"
          first=0
        done
        entries="$entries]"
        aws sqs send-message-batch --queue-url "$QURL" --entries "$entries" >/dev/null &
      done
      wait
    done
    echo "$COUNT mensagens enviadas"'
