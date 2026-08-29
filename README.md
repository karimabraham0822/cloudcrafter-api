# CloudCrafter — Task 1: Foundation (Run + React to Events)

This covers **Part A** (microservices on local Kubernetes behind Ingress) and
**Part B** (LocalStack S3 → Lambda → Notifications event flow).

## Repo layout

```
services/            4 microservices (Users, Events, Tickets, Notifications)
k8s/                 Deployment, Service, and Ingress manifests
charts/              (empty — reserved for Task 2 Helm packaging)
.github/workflows/   (empty — reserved for Task 2 CI/CD)
localstack/          docker-compose for LocalStack + the Lambda source
scripts/             setup and verification helper scripts
```

## Prerequisites

- Docker
- A local Kubernetes cluster: kind, minikube, or Docker Desktop's built-in
  Kubernetes (any works — commands below don't assume a specific one)
- An NGINX Ingress Controller installed on that cluster
  - kind: `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml`
  - minikube: `minikube addons enable ingress`
- awscli (`pip install awscli` or `brew install awscli`) — used to talk to LocalStack
- Node.js 20+ (only if you want to run a service outside Docker)

---

## Part A — Microservices + Ingress on local Kubernetes

### 1. Start your local cluster

```bash
# pick one
kind create cluster --name cloudcrafter
# or
minikube start
```

### 2. Build the service images and load them into the cluster

```bash
./scripts/build-images.sh
```

### 3. Apply the manifests

```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/ -n cloudcrafter
```

(The `-f k8s/` applies every Deployment, Service, and the Ingress in one go —
namespace is applied first since everything else lives inside it.)

### 4. Verify everything runs

```bash
kubectl get pods -n cloudcrafter
kubectl get svc -n cloudcrafter
kubectl get ingress -n cloudcrafter
```

All 8 pods (2 replicas × 4 services) should show `Running` / `1/1 Ready`.

Point `cloudcrafter.local` at your cluster and hit it through Ingress:

```bash
echo "127.0.0.1 cloudcrafter.local" | sudo tee -a /etc/hosts   # kind/Docker Desktop
# minikube: use `minikube ip` instead of 127.0.0.1, or run `minikube tunnel`

curl http://cloudcrafter.local/users/users
curl http://cloudcrafter.local/events/events
curl http://cloudcrafter.local/tickets/tickets
curl http://cloudcrafter.local/notifications/notifications
```

**Part A checklist**
- [ ] Cluster is running
- [ ] Deployments/Services/Ingress applied
- [ ] All 4 services reachable through a single Ingress host

---

## Part B — Event-driven notification (LocalStack S3 → Lambda)

### 1. Start LocalStack

```bash
cd localstack
docker compose up -d
cd ..
```

### 2. Expose the Notifications service to your machine

The Lambda (running in a LocalStack/Docker container) needs to reach the
Notifications pod running inside Kubernetes. Port-forward it in a separate
terminal and leave it running:

```bash
kubectl port-forward svc/notifications 3004:80 -n cloudcrafter
```

### 3. Create the bucket, deploy the Lambda, and wire the S3 event trigger

```bash
./scripts/setup-localstack.sh
```

This creates the `ticket-receipts` bucket, packages and deploys the
`receipt-notifier` Lambda (`localstack/lambda/index.js`), and configures an
S3 `ObjectCreated` event notification so every upload invokes the Lambda
automatically — no manual invocation.

### 4. Prove it works end to end

```bash
./scripts/upload-receipt.sh t1
```

This uploads a sample `ticket-t1-receipt.txt` to the bucket, waits a moment
for the Lambda to fire, then queries the Notifications service. You should
see a notification referencing the uploaded file and ticket `t1`.

You can also check directly:

```bash
curl http://localhost:3004/notifications
```

**Part B checklist**
- [ ] LocalStack running, emulating S3 + Lambda
- [ ] `ticket-receipts` bucket created
- [ ] Lambda deployed and connected to the Notifications service
- [ ] Uploading a receipt fires a notification automatically, no manual trigger

---

## How the event flow works

```
upload receipt.txt
      │
      ▼
S3 bucket (LocalStack): ticket-receipts
      │  ObjectCreated:* event notification
      ▼
Lambda: receipt-notifier (localstack/lambda/index.js)
      │  POST { bucket, key, ticketId, message }
      ▼
Notifications service (k8s pod, reached via port-forward)
      │
      ▼
notification stored + logged — visible at GET /notifications
```

Once both checklists are green, Task 1's foundation is done: the system runs
on Kubernetes, and it reacts to events on its own with no human in the loop.
