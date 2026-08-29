#!/usr/bin/env bash
# Run this BEFORE recording the Task 5 demo. It walks through every
# component built in Tasks 1-4 and reports PASS/FAIL for each, so nothing
# gets discovered broken for the first time on camera.
#
# This does not fix anything — it only checks and reports. Fix any FAIL
# before recording.
set -uo pipefail   # not -e: we want to keep checking even if one check fails

NAMESPACE="${1:-cloudcrafter}"
RESULTS=()
PASS=0
FAIL=0

check() {
  local label="$1"
  local status="$2"   # "PASS" or "FAIL"
  local detail="${3:-}"
  RESULTS+=("$status | $label${detail:+ — $detail}")
  if [ "$status" = "PASS" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
  echo "[$status] $label${detail:+ — $detail}"
}

echo "===================================================="
echo " CloudCrafter Task 5 — Preflight Readiness Check"
echo " Namespace: $NAMESPACE"
echo "===================================================="

# -- Task 1: services + ingress + event flow --------------------------------
echo ""
echo "-- Task 1: core services, Ingress, event-driven notification --"

for svc in users events tickets notifications; do
  READY=$(kubectl get deployment "$svc" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  DESIRED=$(kubectl get deployment "$svc" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
  if [ "$READY" = "$DESIRED" ] && [ "$READY" != "0" ]; then
    check "$svc deployment ready" "PASS" "$READY/$DESIRED replicas"
  else
    check "$svc deployment ready" "FAIL" "$READY/$DESIRED replicas"
  fi
done

if kubectl get ingress cloudcrafter-ingress -n "$NAMESPACE" >/dev/null 2>&1; then
  check "Ingress exists" "PASS"
else
  check "Ingress exists" "FAIL"
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q cloudcrafter-localstack; then
  check "LocalStack container running" "PASS"
else
  check "LocalStack container running" "FAIL" "run: cd localstack && docker compose up -d"
fi

# -- Task 2: Helm + CI + Argo CD + multi-cloud -------------------------------
echo ""
echo "-- Task 2: Helm charts, CI/CD, Argo CD, multi-cloud --"

if command -v helm >/dev/null 2>&1; then
  if helm list -n "$NAMESPACE" 2>/dev/null | grep -q cloudcrafter; then
    check "Helm release installed" "PASS"
  else
    check "Helm release installed" "FAIL"
  fi
else
  check "helm CLI available" "FAIL" "install helm to package/verify charts"
fi

if kubectl get ns argocd >/dev/null 2>&1; then
  APP_HEALTH=$(kubectl get application cloudcrafter -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "unknown")
  APP_SYNC=$(kubectl get application cloudcrafter -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "unknown")
  if [ "$APP_HEALTH" = "Healthy" ] && [ "$APP_SYNC" = "Synced" ]; then
    check "Argo CD app healthy + synced" "PASS" "health=$APP_HEALTH sync=$APP_SYNC"
  else
    check "Argo CD app healthy + synced" "FAIL" "health=$APP_HEALTH sync=$APP_SYNC"
  fi
else
  check "Argo CD installed" "FAIL" "namespace 'argocd' not found"
fi

for ns in aws google-cloud; do
  READY=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
  if [ "$READY" -gt 0 ]; then
    check "'$ns' namespace has running pods" "PASS" "$READY running"
  else
    check "'$ns' namespace has running pods" "FAIL"
  fi
done

# -- Task 3: observability ---------------------------------------------------
echo ""
echo "-- Task 3: Prometheus, Loki, Grafana --"

if kubectl get ns monitoring >/dev/null 2>&1; then
  check "monitoring namespace exists" "PASS"
  for deploy_pattern in "kube-prometheus-stack-grafana" "kube-prometheus-stack-operator"; do
    if kubectl get deploy -n monitoring 2>/dev/null | grep -q "$deploy_pattern"; then
      check "$deploy_pattern running" "PASS"
    else
      check "$deploy_pattern running" "FAIL"
    fi
  done
  if kubectl get pods -n monitoring 2>/dev/null | grep -q loki; then
    check "Loki pod present" "PASS"
  else
    check "Loki pod present" "FAIL"
  fi
else
  check "monitoring namespace exists" "FAIL" "run scripts/setup-observability.sh"
fi

# -- Task 4: JWT rotation ----------------------------------------------------
echo ""
echo "-- Task 4: JWT signing key --"

if kubectl get secret users-jwt-key -n "$NAMESPACE" >/dev/null 2>&1; then
  check "users-jwt-key Secret exists" "PASS"
else
  check "users-jwt-key Secret exists" "FAIL" "run scripts/generate-jwt-key.sh"
fi

echo ""
echo "===================================================="
echo " RESULT: $PASS passed, $FAIL failed"
echo "===================================================="
if [ "$FAIL" -eq 0 ]; then
  echo "Everything checks out. Safe to start recording — follow DEMO_SCRIPT.md."
else
  echo "Fix the FAIL items above before recording."
fi
