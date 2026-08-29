#!/usr/bin/env bash
# Installs Prometheus + Grafana (kube-prometheus-stack) and Loki + Promtail
# (loki-stack) into the "monitoring" namespace, wires up the CloudCrafter
# ServiceMonitors (part of each Helm chart from Task 2), and loads the
# CloudCrafter health dashboard into Grafana.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== 1. Adding Helm repos =="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo "== 2. Creating monitoring namespace =="
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "== 3. Installing kube-prometheus-stack (Prometheus + Grafana + Alertmanager) =="
# Release name MUST be "kube-prometheus-stack" — it's what our ServiceMonitors'
# `release` label matches (see charts/*/values.yaml -> metrics.prometheusReleaseLabel).
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f "$ROOT_DIR/observability/values-kube-prometheus-stack.yaml" \
  --wait --timeout 5m

echo "== 4. Installing Loki + Promtail =="
helm upgrade --install loki grafana/loki-stack \
  -n monitoring \
  -f "$ROOT_DIR/observability/values-loki-stack.yaml" \
  --wait --timeout 5m

echo "== 5. Re-applying CloudCrafter charts so their ServiceMonitors register =="
# (No-op if already installed — this just ensures the ServiceMonitor
# templates added in Task 3 are picked up by an existing release.)
helm dependency build "$ROOT_DIR/charts/cloudcrafter"
helm upgrade --install cloudcrafter "$ROOT_DIR/charts/cloudcrafter" \
  -n cloudcrafter --create-namespace \
  -f "$ROOT_DIR/charts/cloudcrafter/values.yaml"

echo "== 6. Loading the CloudCrafter health dashboard into Grafana =="
"$ROOT_DIR/scripts/generate-dashboard-configmap.sh"
kubectl apply -f "$ROOT_DIR/k8s/monitoring/grafana-dashboard-configmap.yaml"

echo ""
echo "== Done =="
echo "Grafana:    kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"
echo "            user: admin  pass: cloudcrafter-admin (see observability/values-kube-prometheus-stack.yaml)"
echo "Prometheus: kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090"
echo "Run ./scripts/verify-health.sh to confirm metrics + logs are actually flowing."
