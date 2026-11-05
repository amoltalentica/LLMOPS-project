#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELM="${HELM:-helm}"
KUBECTL="${KUBECTL:-kubectl}"
PROFILE="${1:-minikube}"

command -v "$HELM" >/dev/null || { echo "helm is required" >&2; exit 1; }
command -v "$KUBECTL" >/dev/null || { echo "kubectl is required" >&2; exit 1; }

case "$PROFILE" in
  minikube)
    if [ "$("$KUBECTL" config current-context 2>/dev/null || true)" != "minikube" ]; then
      echo "Refusing to install the Minikube profile: current kubectl context is not 'minikube'." >&2
      exit 1
    fi
    VALUES_DIR="$ROOT_DIR/deploy/minikube"
    ;;
  aws-k3s)
    CONTEXT="$("$KUBECTL" config current-context 2>/dev/null || true)"
    if [ -z "${AWS_K3S_CONTEXT:-}" ] || [ "$CONTEXT" != "$AWS_K3S_CONTEXT" ]; then
      echo "Set AWS_K3S_CONTEXT to the expected AWS k3s context ('$CONTEXT') before installing." >&2
      exit 1
    fi
    SERVER="$("$KUBECTL" config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"
    case "$SERVER" in
      https://127.0.0.1*|https://localhost*|http://127.0.0.1*|http://localhost*)
        echo "Refusing AWS profile for local API server: $SERVER" >&2
        exit 1
        ;;
      https://*)
        ;;
      *)
        echo "Cannot confirm a remote Kubernetes API endpoint for context '$CONTEXT': $SERVER" >&2
        exit 1
        ;;
    esac
    VALUES_DIR="$ROOT_DIR/deploy/aws-k3s"
    ;;
  *)
    echo "Usage: $0 [minikube|aws-k3s]" >&2
    exit 2
    ;;
esac

"$KUBECTL" cluster-info >/dev/null

"$HELM" repo add prometheus-community https://prometheus-community.github.io/helm-charts
"$HELM" repo add grafana-community https://grafana-community.github.io/helm-charts
"$HELM" repo add grafana https://grafana.github.io/helm-charts
"$HELM" repo update

"$HELM" upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 92.17.1 \
  --namespace monitoring --create-namespace \
  --values "$VALUES_DIR/prometheus-values.yaml"

"$HELM" upgrade --install loki grafana-community/loki \
  --version 20.4.1 \
  --namespace monitoring --create-namespace \
  --values "$VALUES_DIR/loki-values.yaml"

"$HELM" upgrade --install alloy grafana/alloy \
  --version 1.15.0 \
  --namespace monitoring --create-namespace \
  --values "$ROOT_DIR/deploy/minikube/alloy-values.yaml"

"$HELM" upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.20.2 \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true

"$KUBECTL" wait --for=condition=Established \
  crd/certificates.cert-manager.io crd/issuers.cert-manager.io --timeout=180s

"$HELM" upgrade --install clickhouse-operator \
  oci://ghcr.io/clickhouse/clickhouse-operator-helm \
  --version 0.0.8 \
  --namespace clickhouse-operator --create-namespace

"$KUBECTL" wait --for=condition=Established \
  crd/clickhouseclusters.clickhouse.com crd/keeperclusters.clickhouse.com --timeout=180s

"$HELM" upgrade --install langfuse \
  oci://ghcr.io/langfuse/langfuse-k8s/charts/langfuse \
  --version 2.0.0 \
  --namespace langfuse --create-namespace \
  --values "$VALUES_DIR/langfuse-values.yaml"

echo "Waiting for observability workloads. Langfuse can take several minutes to initialize."
if [ "$PROFILE" = "aws-k3s" ]; then
  "$KUBECTL" kustomize --load-restrictor LoadRestrictionsNone "$ROOT_DIR/deploy/aws-k3s" \
    | "$KUBECTL" apply -f -
else
  "$KUBECTL" apply -f "$ROOT_DIR/deploy/minikube/observability.yaml"
  "$KUBECTL" apply -f "$ROOT_DIR/deploy/minikube/runtime-config.yaml"
fi
"$KUBECTL" -n monitoring rollout status deployment/kube-prometheus-stack-grafana --timeout=600s
"$KUBECTL" -n monitoring rollout status deployment/loki-gateway --timeout=600s
"$KUBECTL" -n langfuse rollout status deployment/langfuse-web --timeout=900s

echo "Observability stack installed for profile: $PROFILE"
