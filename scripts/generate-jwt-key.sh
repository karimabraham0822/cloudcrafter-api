#!/usr/bin/env bash
# Creates the initial JWT signing key as a Kubernetes Secret.
# Run this once before the users Deployment is first installed (or the pods
# will fail to mount /etc/jwt and CrashLoop). scripts/rotate-jwt-key.sh
# handles updating it later.
set -euo pipefail

NAMESPACE="${1:-cloudcrafter}"
SECRET_NAME="users-jwt-key"

echo "== Generating a 512-bit random signing key =="
NEW_KEY=$(openssl rand -hex 64)

echo "== Creating namespace (if needed) =="
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "== Creating Secret '$SECRET_NAME' in namespace '$NAMESPACE' =="
kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=jwt-secret="$NEW_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "== Done. The Secret is not stored anywhere in this repo — it lives only in the cluster. =="
