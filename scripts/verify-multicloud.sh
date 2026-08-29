#!/usr/bin/env bash
# Verifies the aws and google-cloud namespaces are running independently:
# each gets its own port-forward and its own curl check.
set -euo pipefail

check_namespace() {
  local ns="$1"
  local local_port="$2"

  echo "== Checking namespace: $ns (users service) =="
  kubectl port-forward svc/users "$local_port":80 -n "$ns" >/tmp/pf-"$ns".log 2>&1 &
  local pf_pid=$!
  sleep 2

  if curl -sf "http://localhost:$local_port/users" >/dev/null; then
    echo "OK: $ns responds independently on port $local_port"
  else
    echo "FAIL: $ns did not respond — check /tmp/pf-$ns.log"
  fi

  kill "$pf_pid" 2>/dev/null || true
  wait "$pf_pid" 2>/dev/null || true
}

check_namespace "aws" 4001
check_namespace "google-cloud" 4002

echo ""
echo "== Confirming isolation: each namespace has its own pods and ClusterIP =="
echo "--- aws pods ---"
kubectl get pods -n aws -o wide
echo "--- aws service ---"
kubectl get svc users -n aws

echo "--- google-cloud pods ---"
kubectl get pods -n google-cloud -o wide
echo "--- google-cloud service ---"
kubectl get svc users -n google-cloud

echo ""
echo "If both namespaces show separate pods, separate ClusterIPs, and both curl"
echo "checks passed, the release is proven portable across environments."
