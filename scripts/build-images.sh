#!/usr/bin/env bash
# Builds the 4 microservice images and loads them into your local cluster
# so the Deployments (imagePullPolicy: IfNotPresent) can find them without
# needing a registry.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES=(users events tickets notifications)

for svc in "${SERVICES[@]}"; do
  echo "== Building cloudcrafter/$svc:local =="
  docker build -t "cloudcrafter/$svc:local" "$ROOT_DIR/services/$svc"
done

if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -q .; then
  CLUSTER_NAME="$(kind get clusters | head -n1)"
  echo "== Loading images into kind cluster: $CLUSTER_NAME =="
  for svc in "${SERVICES[@]}"; do
    kind load docker-image "cloudcrafter/$svc:local" --name "$CLUSTER_NAME"
  done
elif command -v minikube >/dev/null 2>&1 && minikube status >/dev/null 2>&1; then
  echo "== Loading images into minikube =="
  for svc in "${SERVICES[@]}"; do
    minikube image load "cloudcrafter/$svc:local"
  done
else
  echo "No running kind or minikube cluster detected."
  echo "If you're using Docker Desktop Kubernetes, no image loading is needed —"
  echo "images built locally are already visible to the cluster."
fi

echo "== Done building images =="
