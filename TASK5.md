# CloudCrafter — Task 5: Final Integration & Demo

This is the capstone-closing task: no new infrastructure, just proving
everything from Tasks 1–4 works together, live, and capturing it on video.

## New in this task

```
services/*/index.js          # each now has GET /version — the visible
                              # marker that proves a real deploy happened
charts/*/values.yaml          # serviceVersion + gitSha, bumped by CI
.github/workflows/ci.yml      # now also bumps serviceVersion/gitSha
scripts/
  preflight-check.sh          # run before recording — checks all of Tasks 1-4
  make-demo-change.sh         # the ONE real code change that kicks off CI
  final-verification.sh       # re-runs the full proof set, post-deploy
DEMO_SCRIPT.md                 # shot-by-shot recording guide, in rubric order
```

## The flow, in one sentence

A version bump gets pushed → CI lints, tests, builds, and versions it →
Argo CD notices and syncs → `/version` on the live Ingress endpoint proves
the new build actually landed → then every other subsystem (JWT rotation,
LocalStack event flow, multi-cloud namespaces, Grafana) gets re-verified
against that same live deployment.

---

## 1. Preflight — before you touch record

```bash
./scripts/preflight-check.sh cloudcrafter
```

Checks, with real `kubectl`/`helm` output, not assumptions:
- all 4 Deployments fully ready
- Ingress exists
- LocalStack container running
- Helm release installed
- Argo CD Application `Healthy` + `Synced`
- `aws` and `google-cloud` namespaces have running pods
- `monitoring` namespace + Grafana/Loki present
- `users-jwt-key` Secret exists

Fix every `FAIL` before recording. The whole point of this step is that
nothing gets discovered broken on camera.

## 2. Record, following DEMO_SCRIPT.md

`DEMO_SCRIPT.md` is the shot list, in the exact order the rubric asks for:

1. Code change (real diff) — `scripts/make-demo-change.sh`
2. CI building + versioning it — GitHub Actions tab, live
3. Argo CD detecting + deploying — Argo CD UI, live
4. Services running in Kubernetes — `kubectl get pods`
5. Ingress + inter-service verification — curl through the Ingress host
6. Grafana — metrics + logs panels, visibly healthy
7. Secured login after key rotation — `scripts/rotate-jwt-key.sh`, full output
8. Automatic serverless notification — `scripts/upload-receipt.sh`
9. Multi-cloud namespace check — `scripts/verify-multicloud.sh`

Each segment's commands print their own proof — the video doesn't need
narration explaining why something worked, the terminal output shows it.

## 3. Close with the full verification pass

```bash
./scripts/final-verification.sh
```

Re-checks services, Ingress, `/version`, JWT auth endpoints, the LocalStack
event flow, both cloud namespaces, and points you to Grafana — one script,
one scroll, good as a closing shot or as a standalone terminal-output proof
if a reviewer wants evidence outside the video too.

---

## What you submit

- **Public repository link** — should clearly show:
  - the `services/ k8s/ charts/ .github/workflows/` structure from Task 1–2
  - branch protection active on `main` (Settings → Branches)
  - semantic version tags (`v0.1.0` baseline, plus whatever CI has bumped
    charts to since — `git tag -l` or the repo's Tags page)
- **Demo video link** — following `DEMO_SCRIPT.md`'s order, showing every
  rubric item with real terminal/UI output, understandable without any
  explanation outside the video itself.

## Final checklist (matches the task brief exactly)

- [ ] Helm charts packaged
- [ ] CI pipeline active
- [ ] Argo CD syncing
- [ ] LocalStack event trigger firing
- [ ] `aws` and `google-cloud` namespaces running
- [ ] Monitoring dashboards available
- [ ] JWT key successfully rotated
- [ ] One real update pushed, built, versioned, and auto-deployed on camera
- [ ] Every microservice verified through Ingress
- [ ] Grafana confirms healthy metrics + logs post-deploy
- [ ] JWT rotation proven live: old token rejected, new token accepted
- [ ] Receipt upload proven to fire a notification with no manual trigger
- [ ] Both cloud namespaces proven running + reachable independently
- [ ] Video covers all of the above, in order, self-contained
