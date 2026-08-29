# CloudCrafter — Task 3: Observability

Builds on Tasks 1 and 2. Gives you Prometheus (metrics), Loki (logs), and
Grafana (dashboards combining both) so you can actually see how the system
behaves — especially right after Argo CD syncs a new release.

## New in this task

```
services/*/index.js          # each now exposes /metrics (prom-client)
charts/*/templates/servicemonitor.yaml   # tells Prometheus Operator to scrape it
observability/
  values-kube-prometheus-stack.yaml   # Prometheus + Grafana + Alertmanager
  values-loki-stack.yaml               # Loki + Promtail
  dashboards/cloudcrafter-health.json  # metrics + logs in one Grafana dashboard
k8s/monitoring/                        # generated ConfigMap for the dashboard
scripts/
  setup-observability.sh               # installs the whole stack
  generate-dashboard-configmap.sh      # wraps the dashboard JSON for Grafana
  verify-health.sh                     # proves metrics + logs are flowing
```

## Why three tools, not one

Metrics (Prometheus) tell you *something* is wrong — latency spiked, error
rate jumped. Logs (Loki) tell you *what happened* — the actual error message,
which request, which pod. Grafana puts both in one place so a single
dashboard, checked right after a deploy, confirms performance, correctness,
and overall stability together — not one without the other.

## What each service now exposes

Every microservice (`users`, `events`, `tickets`, `notifications`) has a new
`/metrics` endpoint (via `prom-client`) exposing:
- `http_requests_total{service, method, route, status_code}` — request counts
- `http_request_duration_seconds{service, method, route, status_code}` — a
  histogram, used for the p95 latency panel
- default Node.js process metrics (memory, event loop, GC) prefixed per service
- `notifications` additionally exposes `notifications_fired_total{source}`,
  so you can watch the Task 1 event-driven flow (LocalStack Lambda → here) on
  the same dashboard as everything else

Each chart also got a `templates/servicemonitor.yaml`, so once Prometheus
Operator (installed as part of kube-prometheus-stack) is running, it
auto-discovers and scrapes every service's `/metrics` every 15s — no manual
Prometheus config editing.

---

## 1. Install the stack

```bash
./scripts/setup-observability.sh
```

This adds the `prometheus-community` and `grafana` Helm repos, installs
**kube-prometheus-stack** (Prometheus + Grafana + Alertmanager) and
**loki-stack** (Loki + Promtail) into a `monitoring` namespace, re-applies
the `cloudcrafter` chart so its new ServiceMonitors register, and loads the
`cloudcrafter-health` dashboard into Grafana automatically via the sidecar
pattern (a labeled ConfigMap, no manual dashboard import).

> Promtail runs as a DaemonSet and tails every pod's stdout/stderr on every
> node — that covers all 4 microservices and any Lambda container logs from
> Task 1's LocalStack setup, with zero per-pod configuration.

## 2. Look at it

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
```

Open `http://localhost:3000` — user `admin`, password `cloudcrafter-admin`
(set in `observability/values-kube-prometheus-stack.yaml`; change it before
any real deployment). Go to **Dashboards → CloudCrafter — System Health**.

The dashboard has:
- Pod status by service (are they Running?)
- Request rate and p95 latency per service (performance)
- 5xx error rate per service (correctness)
- Notifications fired over time (proves the event-driven flow from Task 1 is
  still working)
- CPU/memory per pod (resource behavior vs. the requests/limits set in Task 2)
- Live logs for the whole `cloudcrafter` namespace, plus an error/warning-only view

## 3. Verify health after every deploy

```bash
./scripts/verify-health.sh
```

Checks, non-interactively:
- all 4 ServiceMonitor targets show `up` in Prometheus
- `http_requests_total` actually has data (metrics are really flowing, not
  just configured)
- Loki has recent log lines from the `cloudcrafter` namespace

Run this right after Argo CD syncs a new chart version (Task 2). If a bad
release silently broke something, this is what catches it instead of you
finding out from a support ticket.

## Task 3 checklist

- [ ] Prometheus collecting metrics (CPU, memory, request performance, health)
- [ ] Loki aggregating logs from all microservice pods into one place
- [ ] Grafana dashboard visualizing both together
- [ ] `verify-health.sh` confirms system health after an automated deployment
