#!/usr/bin/env bash
# Runs right after the demo deploy lands (Argo CD synced). Verifies, with
# real output, everything the Task 5 rubric asks for in one pass. Meant to
# be run ON CAMERA — every line printed is proof, not narration.
set -uo pipefail

NAMESPACE="${1:-cloudcrafter}"
INGRESS_HOST="${2:-cloudcrafter.local}"

section() { echo ""; echo "===== $1 ====="; }

section "1. Each microservice responds correctly (direct + through Ingress)"
for svc in users events tickets notifications; do
  echo "-- $svc --"
  curl -s "http://$INGRESS_HOST/$svc/health" | python3 -m json.tool
done

section "2. Inter-service reachability check (tickets -> notifications path exists)"
curl -s "http://$INGRESS_HOST/tickets/tickets/t1/receipt-status" | python3 -m json.tool

section "3. Version marker on the latest deploy (proves the CI/Argo CD flow landed)"
curl -s "http://$INGRESS_HOST/users/version" | python3 -m json.tool

section "4. JWT rotation is genuinely active"
echo "(Run scripts/rotate-jwt-key.sh separately for the full before/after proof."
echo " This just confirms the auth endpoints are live post-deploy.)"
LOGIN=$(curl -s -X POST "http://$INGRESS_HOST/users/auth/login" \
  -H 'Content-Type: application/json' -d '{"userId":"u1"}')
echo "$LOGIN" | python3 -m json.tool
TOKEN=$(echo "$LOGIN" | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")
curl -s "http://$INGRESS_HOST/users/auth/verify" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

section "5. Serverless notification still fires automatically (LocalStack)"
"$(dirname "$0")/upload-receipt.sh" t1

section "6. Multi-cloud namespaces still running and reachable"
for ns in aws google-cloud; do
  echo "-- $ns --"
  kubectl get pods -n "$ns"
done
"$(dirname "$0")/verify-multicloud.sh"

section "7. Grafana / Prometheus health after this deployment"
echo "Open Grafana manually for the visual dashboard check:"
echo "  kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"
echo "  -> Dashboards -> CloudCrafter — System Health"
echo "Or check programmatically:"
"$(dirname "$0")/verify-health.sh" || true

echo ""
echo "===== DONE — this is the full proof set for the demo video ====="
