# CloudCrafter — Task 2: Package, Automate, Prove Portable

Builds on Task 1. Covers **Part A** (repo + release discipline), **Part B**
(Helm packaging + CI/CD + Argo CD GitOps), and **Part C** (multi-cloud
namespace proof).

## New in this task

```
charts/
  users/, events/, tickets/, notifications/   # one Helm chart per microservice
  cloudcrafter/                               # umbrella chart (all 4 + ingress)
    values.yaml            # default (single "cloudcrafter" namespace)
    values-aws.yaml         # Part C: aws namespace override
    values-google-cloud.yaml  # Part C: google-cloud namespace override
k8s/
  argocd/application.yaml   # Argo CD Application — GitOps sync target
  multicloud-namespaces.yaml # Part C: aws + google-cloud namespaces
.github/workflows/ci.yml    # lint, test, build, version-bump pipeline
scripts/
  init-repo.sh               # Part A: repo, baseline tag, branch protection
  deploy-multicloud.sh        # Part C: same release into 2 namespaces
  verify-multicloud.sh        # Part C: prove both work independently
```

---

## Part A — Repository and release discipline

### 1. Create the central repo and baseline tag

```bash
./scripts/init-repo.sh cloudcrafter-api <your-github-username-or-org>
```

This runs `git init`, commits the current tree as the clean baseline, tags
it `v0.1.0`, creates the GitHub repo (via `gh`), pushes, and attempts to turn
on branch protection for `main` (PR required + CI checks must pass).

If you don't have `gh` installed/authenticated, the script prints the manual
`git remote` / `git push` commands and tells you exactly what to toggle in
**Settings → Branches** instead.

**Note:** branch protection referencing the `lint-and-test` / `lint-charts`
check names only works after the workflow has run at least once (GitHub
needs to have seen the check). Open one throwaway PR first if the API call
fails, then re-run step 5 of the script.

### Part A checklist
- [ ] Central repo created, starter pushed as clean baseline
- [ ] `main` protected — PRs + passing CI required
- [ ] `v0.1.0` baseline tag created
- [ ] `.github/workflows/` ready (see Part B)

---

## Part B — Helm packaging + CI/CD + Argo CD

### Chart structure

Each of `charts/{users,events,tickets,notifications}` is a standalone chart:
- `Chart.yaml` — name + semantic `version` (bumped automatically by CI)
- `values.yaml` — image, replica count, port, env, and **resource
  requests/limits** (right-sized per service — notifications gets the most
  since it does the most work; users/events are lighter read paths)
- `templates/deployment.yaml`, `templates/service.yaml` — parameterized via
  `.Values`, replacing the raw manifests from Task 1

`charts/cloudcrafter/` is an umbrella chart that pulls all four in as
dependencies plus an Ingress template, so the whole release installs as one
Helm release.

### 1. Try it locally first

```bash
helm dependency build charts/cloudcrafter
helm install cloudcrafter charts/cloudcrafter --namespace cloudcrafter --create-namespace
helm lint charts/*
```

### 2. CI pipeline (`.github/workflows/ci.yml`)

On every PR: lints and syntax-checks all 4 services, runs `helm lint` on
every chart. On merge to `main`: builds and pushes each service image to
GHCR, then **bumps that chart's patch version** and updates its
`values.yaml` image tag, committing straight back to `main`.

That commit — a new chart version pointing at a new image — is the signal
Argo CD watches for.

### 3. Connect Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# edit repoURL in k8s/argocd/application.yaml to your actual repo, then:
kubectl apply -f k8s/argocd/application.yaml
```

With `syncPolicy.automated` set (prune + selfHeal), Argo CD polls the repo,
notices the chart version CI just bumped, and syncs the cluster to match —
no manual `helm upgrade`, no manual `kubectl apply`.

Access the UI to watch it happen:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Part B checklist
- [ ] Deployment + Service templates + values.yaml for all 4 services
- [ ] CPU/memory requests and limits set per service
- [ ] CI lints, tests, builds images, bumps chart versions
- [ ] Argo CD Application applied and actively syncing

---

## Part C — Prove the release is portable (multi-cloud simulation)

### 1. Deploy the identical release into two namespaces

```bash
./scripts/deploy-multicloud.sh
```

This creates the `aws` and `google-cloud` namespaces, then installs
**the exact same `charts/cloudcrafter` chart** into both — the only thing
that differs is which values file sets the namespace
(`values-aws.yaml` vs `values-google-cloud.yaml`). No template, no image, no
resource setting changes between the two installs.

### 2. Verify both independently

```bash
./scripts/verify-multicloud.sh
```

This port-forwards into `aws` and `google-cloud` separately, curls each,
and prints each namespace's pods + ClusterIP so you can see they're fully
isolated from one another.

### Part C checklist
- [ ] `aws` and `google-cloud` namespaces created
- [ ] Identical Helm release deployed to both, unmodified
- [ ] Each verified independently via port-forward — separate pods, separate ClusterIPs

---

## Why this matters

By the end of Task 2:
- A code change → CI builds, versions, and commits → Argo CD deploys, with
  zero manual steps (Part B).
- The *same* artifact that Argo CD deploys can be `helm install`ed into any
  namespace/cluster with only a values override (Part C) — proof there's no
  hidden environment coupling.

That combination — automated *and* portable — is what "shippable release"
means in this capstone.
