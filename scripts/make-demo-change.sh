#!/usr/bin/env bash
# The ONE real code change for the Task 5 demo: bumps the visible
# SERVICE_VERSION default across all 4 services and pushes it to main.
# This is what CI picks up, builds, and versions, and what Argo CD then
# syncs — the exact flow built in Task 2, proven for real here.
#
# Run this on camera (or right before recording the "code change" segment)
# so the diff is genuinely new, not staged in advance.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

NEW_VERSION="${1:-}"
if [ -z "$NEW_VERSION" ]; then
  # Auto-suggest: bump the users service's current default patch version.
  CURRENT=$(grep -o "SERVICE_VERSION || '[0-9.]*'" services/users/index.js | grep -o "[0-9.]*")
  IFS='.' read -r MAJ MIN PAT <<< "$CURRENT"
  NEW_VERSION="$MAJ.$MIN.$((PAT + 1))"
fi

echo "== Bumping SERVICE_VERSION default to $NEW_VERSION across all 4 services =="
for svc in users events tickets notifications; do
  sed -i "s/SERVICE_VERSION || '[0-9.]*'/SERVICE_VERSION || '$NEW_VERSION'/" "services/$svc/index.js"
  node --check "services/$svc/index.js"
  echo "  services/$svc/index.js -> $NEW_VERSION"
done

echo "== Committing and pushing =="
git add services/*/index.js
git commit -m "feat: bump service version to $NEW_VERSION (Task 5 demo release)"
git push origin main

echo ""
echo "== Done. Now: =="
echo "  1. Open your GitHub repo's Actions tab — CI is running now."
echo "  2. Once CI finishes, it commits a chart version bump back to main."
echo "  3. Open Argo CD (kubectl port-forward svc/argocd-server -n argocd 8080:443)"
echo "     and watch the 'cloudcrafter' Application sync automatically."
echo "  4. Once synced, run: curl http://cloudcrafter.local/users/version"
echo "     It should show version: \"$NEW_VERSION\"."
