#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MINIKUBE="${MINIKUBE:-minikube}"
KUBECTL="${KUBECTL:-kubectl}"

command -v "$MINIKUBE" >/dev/null || { echo "minikube is required" >&2; exit 1; }
command -v "$KUBECTL" >/dev/null || { echo "kubectl is required" >&2; exit 1; }

"$MINIKUBE" status
"$MINIKUBE" image build -t order-service:local "$ROOT_DIR/services/order-service"
"$MINIKUBE" image build -t product-service:local "$ROOT_DIR/services/product-service"
"$MINIKUBE" image build -t sre-agent:local "$ROOT_DIR/services/sre-agent"
"$KUBECTL" kustomize --load-restrictor LoadRestrictionsNone "$ROOT_DIR/deploy/minikube" \
  | "$KUBECTL" apply -f -
"$KUBECTL" -n ai-agent rollout status deployment/sre-agent --timeout=300s
"$KUBECTL" -n apps rollout status deployment/order-service --timeout=300s
"$KUBECTL" -n apps rollout status deployment/product-service --timeout=300s

echo "Application deployed. Use 'minikube service -n ai-agent sre-agent' to open the agent API."
