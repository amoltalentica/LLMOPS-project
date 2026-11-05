#!/bin/bash
###############################################################################
# trigger-chaos-rca.sh
#
# Simulates failure in microservices and triggers automated RCA with email!
#
# Usage:
#   ./scripts/trigger-chaos-rca.sh crash-order   [EMAIL]
#   ./scripts/trigger-chaos-rca.sh oom-product   [EMAIL]
#   ./scripts/trigger-chaos-rca.sh db-exhaustion [EMAIL]
#   ./scripts/trigger-chaos-rca.sh bad-image-order [EMAIL]  # Minikube only; rolls back after RCA
#   ./scripts/trigger-chaos-rca.sh latency-product [EMAIL]
###############################################################################
set -euo pipefail

# Ensure correct kubeconfig is loaded
if [ -z "${KUBECONFIG:-}" ] && [ -f "$HOME/.kube/ai-sre-agent-prod.yaml" ]; then
    export KUBECONFIG="$HOME/.kube/ai-sre-agent-prod.yaml"
fi

SCENARIO="${1:-crash-order}"
RECIPIENT_EMAIL="${2:-}"

# Auto-detect cluster public IP from kubeconfig if not explicitly set
CLUSTER_IP=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null | sed -E 's|https?://([^:]+):.*|\1|' || true)
if [ "$(kubectl config current-context 2>/dev/null || true)" = "minikube" ] && command -v minikube >/dev/null 2>&1; then
    CLUSTER_IP=$(minikube ip)
fi
if [ -z "$CLUSTER_IP" ] || [ "$CLUSTER_IP" = "kubernetes.default.svc" ]; then
    CLUSTER_IP="localhost"
fi

AGENT_HOST="${AGENT_HOST:-${CLUSTER_IP}:30080}"
ORDER_HOST="${ORDER_HOST:-${CLUSTER_IP}:30081}"
PRODUCT_HOST="${PRODUCT_HOST:-${CLUSTER_IP}:30082}"
WAIT_SECONDS=10
RESTORE_ORDER=false

cleanup() {
  if [ "$RESTORE_ORDER" = true ]; then
    echo "==> Restoring order-service deployment..."
    kubectl -n apps rollout undo deployment/order-service >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Auto-fetch agent_api_key from Kubernetes secret if not exported
AGENT_API_KEY="${AGENT_API_KEY:-}"
if [ -z "$AGENT_API_KEY" ]; then
    AGENT_API_KEY=$(kubectl -n ai-agent get secret agent-secrets -o jsonpath='{.data.agent_api_key}' 2>/dev/null | base64 -d 2>/dev/null || true)
fi

echo "=========================================================="
echo " RCA Chaos Injection & Diagnostic Engine"
echo " Scenario:    $SCENARIO"
echo " Order Host:  http://${ORDER_HOST}"
echo " Product Host: http://${PRODUCT_HOST}"
echo " Agent Host:  http://${AGENT_HOST}"
echo "=========================================================="

case "$SCENARIO" in
  crash-order)
    echo "==> Injecting Fatal Crash into Order Service (os._exit)..."
    curl -s -m 5 -X POST "http://${ORDER_HOST}/chaos/crash" || true
    echo "==> Crash injected. Kubernetes will detect failure and enter CrashLoopBackOff."
    ;;
  oom-product)
    echo "==> Injecting Memory Exhaustion into Product Service (/chaos/oom)..."
    curl -s -m 5 -X POST "http://${PRODUCT_HOST}/chaos/oom" || true
    echo "==> Memory spike injected. Cgroup killer will issue SIGKILL 137 (OOMKilled)."
    ;;
  db-exhaustion)
    echo "==> Simulating DB Connection Pool Exhaustion in Order Service..."
    curl -s -m 5 -X POST "http://${ORDER_HOST}/chaos/db-error" || true
    echo "==> Simulated database connection timeout."
    ;;
  bad-image-order)
    if [ "$(kubectl config current-context 2>/dev/null || true)" != "minikube" ]; then
      echo "bad-image-order is restricted to the Minikube context." >&2
      exit 1
    fi
    echo "==> Deploying a deliberately missing order-service image..."
    RESTORE_ORDER=true
    kubectl -n apps set image deployment/order-service \
      order-service=example.invalid/order-service:missing-demo-image
    WAIT_SECONDS=25
    ;;
  latency-product)
    echo "==> Generating a 15-second product-service latency sample..."
    curl -s -m 20 -X POST "http://${PRODUCT_HOST}/chaos/latency?seconds=15" || true
    ;;
  *)
    echo "Unknown scenario: $SCENARIO"
    echo "Options: crash-order | oom-product | db-exhaustion | bad-image-order | latency-product"
    exit 1
    ;;
esac

echo "==> Waiting ${WAIT_SECONDS} seconds for Kubernetes events and logs to update..."
sleep "$WAIT_SECONDS"

echo "==> Invoking AI SRE Agent RCA Endpoint..."
EMAIL_PAYLOAD=""
if [ -n "$RECIPIENT_EMAIL" ]; then
  EMAIL_PAYLOAD="\"email_to\": [\"$RECIPIENT_EMAIL\"],"
fi

AUTH_HEADER=()
if [ -n "$AGENT_API_KEY" ]; then
  AUTH_HEADER=(-H "x-api-key: ${AGENT_API_KEY}")
fi

RCA_RESPONSE=$(curl -s -X POST "http://${AGENT_HOST}/rca" \
  -H "Content-Type: application/json" \
  "${AUTH_HEADER[@]}" \
  -d "{
    ${EMAIL_PAYLOAD}
    \"question\": \"Investigate recent anomalies or failing pods in the apps namespace and generate an incident RCA.\"
  }")

echo ""
echo "=========================================================="
echo " Root Cause Analysis (RCA) Result"
echo "=========================================================="
echo "$RCA_RESPONSE" | jq -r '
  "Title:       " + .rca.title + "\n" +
  "Severity:    " + .rca.severity + "\n" +
  "Confidence:  " + .rca.confidence + "\n" +
  "Root Cause:  " + .rca.root_cause + "\n" +
  "Report File: " + .report_file + "\n" +
  "Emailed:     " + (.emailed | tostring)
' 2>/dev/null || echo "$RCA_RESPONSE"

echo "=========================================================="
echo "View full HTML report in browser at: http://${AGENT_HOST}/rca/latest"
echo "=========================================================="
