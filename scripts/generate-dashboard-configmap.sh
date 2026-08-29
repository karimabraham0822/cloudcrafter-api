#!/usr/bin/env bash
# Wraps observability/dashboards/cloudcrafter-health.json in a ConfigMap
# labeled grafana_dashboard=1, which the Grafana sidecar (enabled in
# observability/values-kube-prometheus-stack.yaml) auto-discovers and loads.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DASHBOARD_JSON="$ROOT_DIR/observability/dashboards/cloudcrafter-health.json"
OUT_FILE="$ROOT_DIR/k8s/monitoring/grafana-dashboard-configmap.yaml"

kubectl create configmap cloudcrafter-health-dashboard \
  --from-file=cloudcrafter-health.json="$DASHBOARD_JSON" \
  -n monitoring \
  --dry-run=client -o yaml > "$OUT_FILE"

# Add the label the sidecar watches for.
python3 - "$OUT_FILE" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path) as f:
    doc = yaml.safe_load(f)
doc.setdefault("metadata", {}).setdefault("labels", {})["grafana_dashboard"] = "1"
with open(path, "w") as f:
    yaml.safe_dump(doc, f, default_flow_style=False)
PY

echo "Wrote $OUT_FILE"
echo "Apply it with: kubectl apply -f $OUT_FILE"
