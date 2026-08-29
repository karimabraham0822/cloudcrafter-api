# CloudCrafter — Task 5 Demo Recording Script

Follow this in order. Every segment maps to a rubric line item, and every
command produces real, on-screen proof — nothing here is narrated without
being shown.

Run `./scripts/preflight-check.sh` first, off camera. Don't start recording
until it reports 0 failures.

---

## Before you hit record

```bash
./scripts/preflight-check.sh cloudcrafter
```
Fix anything marked FAIL. This is the checklist from the task brief —
nothing should get discovered broken for the first time on camera.

---

## Segment 1 — The code change (Task 2 proof, start)

**Show:** your editor or terminal, the actual diff.

```bash
git diff   # after running make-demo-change.sh, or show it live
```

Narrate/caption: "This is the one real update — a version bump across all
four services." Then:

```bash
./scripts/make-demo-change.sh
```

This commits and pushes to `main`.

## Segment 2 — CI builds and versions it

**Show:** your GitHub repo's **Actions** tab, live, as the workflow runs.
Point out the four jobs in order: `lint-and-test` → `lint-charts` →
`build-and-push` → `bump-chart-version`. Let the last job finish — that's
the commit that bumps `charts/*/Chart.yaml` and `values.yaml` automatically.

```bash
git pull && git log --oneline -3
```
Show the `ci: bump ... chart + image tag` commit CI just made.

## Segment 3 — Argo CD detects and deploys it

**Show:** the Argo CD UI.

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Open `https://localhost:8080`, find the `cloudcrafter` Application, and
either wait for or trigger the sync. Show the sync graph turning green /
"Synced" + "Healthy".

## Segment 4 — Services running in Kubernetes

```bash
kubectl get pods -n cloudcrafter
kubectl get pods -n cloudcrafter -o jsonpath='{.items[*].spec.containers[*].image}'
```
Point out the new image tag matches what CI just built.

## Segment 5 — Ingress + inter-service verification

```bash
curl http://cloudcrafter.local/users/health
curl http://cloudcrafter.local/events/health
curl http://cloudcrafter.local/tickets/health
curl http://cloudcrafter.local/notifications/health
curl http://cloudcrafter.local/users/version
```
The `/version` response should show the version you just bumped in Segment
1 — that's the whole pipeline proven in one JSON response.

## Segment 6 — Grafana: metrics and logs still healthy

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
```
Open `http://localhost:3000` → **Dashboards → CloudCrafter — System Health**.
Show, on screen:
- Pod status panel — all green/running
- Request rate + p95 latency panels — normal, no spikes
- 5xx error rate — flat at zero
- Live logs panel — recent lines actively streaming in

## Segment 7 — Secured login after key rotation (Task 4 proof)

```bash
./scripts/rotate-jwt-key.sh cloudcrafter
```
Let the full script run on camera — it prints the old token, rotates the
key, restarts with zero downtime, then shows the old token getting `401`
and a new token getting `200`. The final `ROTATION SUMMARY` block is your
proof; let it stay on screen for a few seconds.

## Segment 8 — Automatic serverless notification (Task 1 proof)

```bash
curl http://localhost:3004/notifications   # baseline: show current count
./scripts/upload-receipt.sh t1
curl http://localhost:3004/notifications   # show the new entry appended
```
Also show the Lambda's own log output for that invocation, if visible:
```bash
docker logs cloudcrafter-localstack --tail 50 | grep -i receipt-notifier
```

## Segment 9 — Multi-cloud namespace check (Task 2 Part C proof)

```bash
./scripts/verify-multicloud.sh
```
Show both `aws` and `google-cloud` namespaces responding independently,
with separate pods and separate ClusterIPs printed on screen.

---

## Closing shot

```bash
./scripts/final-verification.sh
```
This re-runs the whole proof set in one script — a good way to close the
video with everything summarized in one terminal scroll.

---

## Recording checklist (tick off before uploading)

- [ ] Code change shown as a real diff, not staged/hidden
- [ ] CI pipeline shown running live (Actions tab), all jobs green
- [ ] Argo CD shown detecting and syncing the change
- [ ] All 4 services verified via Ingress
- [ ] `/version` response proves the new build actually deployed
- [ ] Grafana dashboard shown with live metrics + live logs
- [ ] JWT rotation shown end-to-end: old token 401, new token 200
- [ ] Receipt upload shown triggering a notification with no manual step
- [ ] Both `aws` and `google-cloud` namespaces shown running independently
- [ ] Video flows in the required order and needs no external explanation
