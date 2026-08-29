# CloudCrafter — Task 4: Security Hardening (JWT Key Rotation)

Builds on Tasks 1–3. Hardens the Users service's authentication layer by
rotating its JWT signing key with zero downtime, and proving — not just
claiming — that old tokens are rejected and new tokens are accepted.

## New in this task

```
services/users/index.js         # now reads JWT key from a mounted Secret,
                                 # adds POST /auth/login and GET /auth/verify
charts/users/templates/deployment.yaml   # RollingUpdate strategy + Secret volume mount
charts/users/values.yaml         # jwt.* config block
scripts/
  generate-jwt-key.sh            # creates the INITIAL key (run once, before first deploy)
  rotate-jwt-key.sh               # rotates the key + zero-downtime restart + proof
```

## How the key is handled

- The signing key **never appears in the repo, the image, or an env var
  baked into a manifest**. It's a Kubernetes Secret (`users-jwt-key`),
  mounted as a read-only file at `/etc/jwt/jwt-secret`.
- The app reads that file once at process startup and logs a **SHA-256
  fingerprint** of the key (never the key itself) — enough to visually
  confirm a rotation happened by watching logs change, without ever
  exposing the secret.
- Because the key is read at startup, a Secret update alone doesn't rotate
  anything live — pods need to restart to pick it up. That's intentional:
  it's what makes the rolling restart step meaningful and observable,
  rather than a silent background change.

## Zero-downtime rollout

`charts/users/templates/deployment.yaml` sets:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```
`maxUnavailable: 0` means Kubernetes never takes a pod down until its
replacement is up **and passing the readiness probe** (`GET /health`). That
readiness gate is what actually prevents a half-restarted pod — one that
hasn't finished loading the new key — from receiving traffic.

---

## 1. First-time setup (only needed once, before the Users Deployment exists)

```bash
./scripts/generate-jwt-key.sh cloudcrafter
```

Creates the initial `users-jwt-key` Secret with a random 512-bit key. Do
this before `helm install`ing the users chart for the first time, or the
pod will fail to mount `/etc/jwt` and CrashLoop.

## 2. Rotate the key

```bash
./scripts/rotate-jwt-key.sh cloudcrafter
```

This is the whole Task 4 story in one script:

1. **Logs in** with the current key to get an "old" token, and sanity-checks
   it's valid right now.
2. **Generates a new key** and updates the `users-jwt-key` Secret.
3. **Starts a background availability probe** hitting `/health` every 0.5s.
4. **Triggers `kubectl rollout restart deployment/users`** and waits for it
   to complete, while the probe keeps running underneath it.
5. **Stops the probe and reports**: total requests during the rollout vs.
   how many were non-200 — this is the zero-downtime proof, not an assertion.
6. **Confirms the old token is now rejected** — calls `/auth/verify` with
   the pre-rotation token and expects `401`.
7. **Confirms a freshly issued token is accepted** — logs in again (now
   signed with the new key) and expects `200` from `/auth/verify`.
8. Prints a summary: old/new key fingerprints, zero-downtime yes/no, old
   token rejected yes/no, new token accepted yes/no.

Nothing in the summary is taken on faith — every line is a real HTTP
response code checked in that run.

### Example summary output

```
== ROTATION SUMMARY ==
  Old key fingerprint: 3f9a2c8b1d4e
  New key fingerprint: 7b1e4f9a0c2d
  Zero downtime:       YES
  Old token rejected:  YES
  New token accepted:  YES
```

If any line says NO, the rotation is not done — re-check
`/tmp/rotation-availability.log` (per-request results during rollout) or
the `kubectl rollout status` / `kubectl logs` output for the users pods.

## Task 4 checklist

- [ ] New JWT key pair generated and stored as a Kubernetes Secret (never in the repo)
- [ ] Secret correctly mounted into the Users Deployment (`/etc/jwt/jwt-secret`)
- [ ] Rolling restart completed with zero downtime (`maxUnavailable: 0`, verified by the availability probe)
- [ ] Old token confirmed rejected (`401` from `/auth/verify`)
- [ ] New token confirmed accepted (`200` from `/auth/verify`)
