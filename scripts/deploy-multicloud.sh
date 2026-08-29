#!/usr/bin/env bash
# Part C: deploys the exact same Helm release (charts/cloudcrafter) into two
# independent namespaces — aws and google-cloud — proving the release is
# portable and not hardcoded to one environment.
#
# The chart itself is never modified between the two installs. Only the
# namespace-scoped values file changes (values-aws.yaml / values-google-cloud.yaml),
# which sets the target namespace and ingress host — everything else
# (image, resources, replica count, templates) is identical.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="$ROOT_DIR/charts/cloudcrafter"

echo "== 1. Creating the two simulated cloud namespaces =="
kubectl apply -f "$ROOT_DIR/k8s/multicloud-namespaces.yaml"

echo "== 2. Building chart dependencies =="
helm dependency build "$CHART_DIR"

echo "== 3. Installing release into 'aws' namespace =="
helm upgrade --install cloudcrafter-aws "$CHART_DIR" \
  --namespace aws \
  -f "$CHART_DIR/values-aws.yaml"

echo "== 4. Installing the SAME chart, unmodified, into 'google-cloud' namespace =="
helm upgrade --install cloudcrafter-gcp "$CHART_DIR" \
  --namespace google-cloud \
  -f "$CHART_DIR/values-google-cloud.yaml"

echo "== Done. Verifying both are up =="
echo "--- aws namespace ---"
kubectl get pods,svc -n aws
echo "--- google-cloud namespace ---"
kubectl get pods,svc -n google-cloud

echo ""
echo "Next: run scripts/verify-multicloud.sh to confirm both respond independently."
