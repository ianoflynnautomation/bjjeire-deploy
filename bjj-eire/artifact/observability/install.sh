#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CHART_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly NAMESPACE="observability"
readonly APP_NAMESPACE="bjjeire-app"

readonly KPS_VERSION="86.2.3"
readonly LOKI_VERSION="7.0.0"
readonly TEMPO_VERSION="1.24.4"
readonly OTEL_VERSION="0.158.1"

mode="${1:-light}"

require_minikube() {
  local context
  context="$(kubectl config current-context)"
  if [[ "${context}" != "minikube" ]]; then
    echo "Refusing to modify Kubernetes context '${context}'. Switch to minikube first." >&2
    exit 1
  fi
}

add_repositories() {
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
  helm repo add grafana https://grafana.github.io/helm-charts --force-update
  helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts --force-update
  helm repo update
}

install_metrics() {
  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
    --namespace "${NAMESPACE}" \
    --version "${KPS_VERSION}" \
    --values "${SCRIPT_DIR}/values/kube-prometheus-stack.yaml" \
    "$@" \
    --wait \
    --timeout 10m

  kubectl apply -f "${SCRIPT_DIR}/manifests/bjj-api-monitoring.yaml"
  kubectl apply -f "${SCRIPT_DIR}/manifests/bjj-api-dashboard.yaml"
  kubectl apply -f "${SCRIPT_DIR}/manifests/mongodb-monitoring.yaml"
  kubectl apply -f "${SCRIPT_DIR}/manifests/mongodb-dashboard.yaml"
}

configure_app() {
  local profile="$1"
  local values=(
    --values "${CHART_DIR}/values.yaml"
    --values "${CHART_DIR}/values-local.yaml"
  )

  if [[ "${profile}" == "full" ]]; then
    values+=(--values "${CHART_DIR}/values-observability.yaml")
  fi

  helm upgrade --install bjj-eire "${CHART_DIR}" \
    --namespace "${APP_NAMESPACE}" \
    --create-namespace \
    --reset-values \
    "${values[@]}" \
    --no-hooks \
    --wait \
    --timeout 10m
}

install_full() {
  helm upgrade --install loki grafana/loki \
    --namespace "${NAMESPACE}" \
    --version "${LOKI_VERSION}" \
    --values "${SCRIPT_DIR}/values/loki.yaml" \
    --wait \
    --timeout 10m

  helm upgrade --install tempo grafana/tempo \
    --namespace "${NAMESPACE}" \
    --version "${TEMPO_VERSION}" \
    --values "${SCRIPT_DIR}/values/tempo.yaml" \
    --wait \
    --timeout 10m

  helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
    --namespace "${NAMESPACE}" \
    --version "${OTEL_VERSION}" \
    --values "${SCRIPT_DIR}/values/opentelemetry-collector.yaml" \
    --wait \
    --timeout 10m

  # Acceptance-test trends dashboard queries Tempo (TraceQL metrics), so it is
  # only installed with the full profile.
  kubectl apply -f "${SCRIPT_DIR}/manifests/bjjeire-tests-dashboard.yaml"
}

remove_full() {
  kubectl delete -f "${SCRIPT_DIR}/manifests/bjjeire-tests-dashboard.yaml" --ignore-not-found
  helm uninstall otel-collector --namespace "${NAMESPACE}" --ignore-not-found
  helm uninstall tempo --namespace "${NAMESPACE}" --ignore-not-found
  helm uninstall loki --namespace "${NAMESPACE}" --ignore-not-found
}

case "${mode}" in
  light)
    require_minikube
    add_repositories
    remove_full
    install_metrics
    configure_app light
    ;;
  full)
    require_minikube
    add_repositories
    install_metrics --values "${SCRIPT_DIR}/values/kube-prometheus-stack-full.yaml"
    install_full
    configure_app full
    ;;
  status)
    require_minikube
    helm list --namespace "${NAMESPACE}"
    kubectl get pods,services --namespace "${NAMESPACE}"
    kubectl get servicemonitor,prometheusrule --all-namespaces
    ;;
  cleanup)
    require_minikube
    remove_full
    helm uninstall monitoring --namespace "${NAMESPACE}" --ignore-not-found
    kubectl delete namespace "${NAMESPACE}" --ignore-not-found
    kubectl delete servicemonitor,prometheusrule bjj-api \
      --namespace "${APP_NAMESPACE}" \
      --ignore-not-found
    configure_app light
    ;;
  *)
    echo "Usage: $0 {light|full|status|cleanup}" >&2
    exit 1
    ;;
esac
