#!/usr/bin/env bash
# Confirms the observability stack is actually working end to end:
# - Prometheus has all 4 CloudCrafter ServiceMonitor targets UP
# - each service's /metrics is returning real request data
# - Loki has recent log lines from the cloudcrafter namespace
#
# Run this any time, but especially right after Argo CD syncs a new
# release, to confirm the deploy didn't silently break anything.
set -euo pipefail

PROM_PORT=9090
GRAFANA_PORT=3000
LOKI_PORT=3100

cleanup() {
  kill "${PROM_PID:-}" "${LOKI_PID:-}" 2>/dev/null || true
}
trap cleanup EXIT

echo "== 1. Port-forwarding Prometheus =="
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring "$PROM_PORT":9090 >/tmp/pf-prom.log 2>&1 &
PROM_PID=$!
sleep 3

echo "== 2. Checking ServiceMonitor targets are UP =="
TARGETS_JSON=$(curl -s "http://localhost:$PROM_PORT/api/v1/targets")
for svc in users events tickets notifications; do
  UP=$(echo "$TARGETS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
active = data.get('data', {}).get('activeTargets', [])
matches = [t for t in active if t.get('labels', {}).get('app') == '$svc' or '$svc' in t.get('scrapePool', '')]
print('up' if any(t.get('health') == 'up' for t in matches) else 'down/missing')
")
  echo "  $svc: $UP"
done

echo "== 3. Checking request metrics are actually flowing (http_requests_total) =="
curl -s "http://localhost:$PROM_PORT/api/v1/query?query=sum(http_requests_total)" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
result = data.get('data', {}).get('result', [])
if result:
    print('  http_requests_total =', result[0]['value'][1])
else:
    print('  No data yet — hit a service endpoint a few times, then re-run this script.')
"

echo "== 4. Port-forwarding Loki =="
kubectl port-forward svc/loki -n monitoring "$LOKI_PORT":3100 >/tmp/pf-loki.log 2>&1 &
LOKI_PID=$!
sleep 3

echo "== 5. Checking Loki has recent logs from cloudcrafter namespace =="
NOW_NS=$(date +%s)000000000
FROM_NS=$(( $(date +%s) - 900 ))000000000
curl -s -G "http://localhost:$LOKI_PORT/loki/api/v1/query_range" \
  --data-urlencode 'query={namespace="cloudcrafter"}' \
  --data-urlencode "start=$FROM_NS" \
  --data-urlencode "end=$NOW_NS" \
  --data-urlencode "limit=5" \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
streams = data.get('data', {}).get('result', [])
total_lines = sum(len(s.get('values', [])) for s in streams)
print(f'  Found {total_lines} recent log lines across {len(streams)} streams')
"

echo ""
echo "== Summary =="
echo "If all 4 services show 'up' and both metrics and logs returned data,"
echo "the system is confirmed healthy. Open Grafana for the full picture:"
echo "  kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring $GRAFANA_PORT:80"
echo "  then open http://localhost:$GRAFANA_PORT -> Dashboards -> CloudCrafter — System Health"
