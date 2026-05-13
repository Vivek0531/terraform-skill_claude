#!/usr/bin/env bash
# verify-kafka.sh — smoke-test Kafka topics and connectivity on the cluster
set -euo pipefail

NAMESPACE="${1:-kafka}"
BOOTSTRAP="kafka.${NAMESPACE}.svc.cluster.local:9092"

echo "==> Verifying Kafka in namespace: ${NAMESPACE}"

# Check pods
echo "==> Pod status:"
kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=kafka

# List topics
echo ""
echo "==> Kafka topics:"
kubectl exec -n "${NAMESPACE}" \
  "$(kubectl get pod -n "${NAMESPACE}" -l app.kubernetes.io/component=broker -o jsonpath='{.items[0].metadata.name}')" -- \
  kafka-topics.sh --bootstrap-server "${BOOTSTRAP}" --list

# Consumer group lag
echo ""
echo "==> Consumer group summary:"
kubectl exec -n "${NAMESPACE}" \
  "$(kubectl get pod -n "${NAMESPACE}" -l app.kubernetes.io/component=broker -o jsonpath='{.items[0].metadata.name}')" -- \
  kafka-consumer-groups.sh --bootstrap-server "${BOOTSTRAP}" --list 2>/dev/null || echo "No consumer groups yet"

# Produce + consume a test message
echo ""
echo "==> Sending test message to payments.initiated..."
kubectl exec -n "${NAMESPACE}" \
  "$(kubectl get pod -n "${NAMESPACE}" -l app.kubernetes.io/component=broker -o jsonpath='{.items[0].metadata.name}')" -- \
  bash -c "echo 'test-payment-event-$(date +%s)' | kafka-console-producer.sh \
    --bootstrap-server ${BOOTSTRAP} \
    --topic payments.initiated"

echo "==> Reading test message from payments.initiated..."
kubectl exec -n "${NAMESPACE}" \
  "$(kubectl get pod -n "${NAMESPACE}" -l app.kubernetes.io/component=broker -o jsonpath='{.items[0].metadata.name}')" -- \
  kafka-console-consumer.sh \
    --bootstrap-server "${BOOTSTRAP}" \
    --topic payments.initiated \
    --from-beginning \
    --max-messages 1 \
    --timeout-ms 10000

echo ""
echo "==> Kafka verification complete"
