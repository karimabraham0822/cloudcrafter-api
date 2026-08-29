#!/usr/bin/env bash
# Part A: creates the central repo, marks a clean baseline, tags it, and
# turns on branch protection (requires GitHub CLI `gh`, already authenticated).
set -euo pipefail

REPO_NAME="${1:-cloudcrafter-api}"
GH_OWNER="${2:-}"   # your GitHub username or org; if empty, gh uses your default account

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== 1. Initializing git repo (if not already) =="
if [ ! -d .git ]; then
  git init
  git checkout -b main
fi

echo "== 2. Baseline commit =="
git add .
git commit -m "chore: import starter project as clean baseline" || echo "(nothing to commit, continuing)"

echo "== 3. Tagging the baseline =="
git tag -a v0.1.0 -m "Baseline: starter project running on Kubernetes (Task 1 complete)"

echo "== 4. Creating the GitHub repo and pushing =="
if command -v gh >/dev/null 2>&1; then
  if [ -n "$GH_OWNER" ]; then
    gh repo create "$GH_OWNER/$REPO_NAME" --private --source=. --remote=origin --push
  else
    gh repo create "$REPO_NAME" --private --source=. --remote=origin --push
  fi
  git push origin main --tags

  echo "== 5. Enabling branch protection on main (PR + passing CI required) =="
  OWNER_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
  gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    "/repos/${OWNER_REPO}/branches/main/protection" \
    -f "required_status_checks[strict]=true" \
    -f "required_status_checks[contexts][]=lint-and-test" \
    -f "required_status_checks[contexts][]=lint-charts" \
    -F "enforce_admins=true" \
    -f "required_pull_request_reviews[required_approving_review_count]=1" \
    -F "restrictions=null" \
    || echo "NOTE: branch protection API call failed — the CI workflow needs to have run at least once before GitHub recognizes those check names. Re-run this step after your first PR, or set it up via Settings > Branches in the UI."
else
  echo "GitHub CLI ('gh') not found. Create the repo manually at github.com,"
  echo "then run:"
  echo "  git remote add origin https://github.com/<owner>/$REPO_NAME.git"
  echo "  git push -u origin main --tags"
  echo "Then enable branch protection under Settings > Branches: require a PR,"
  echo "require the 'lint-and-test' and 'lint-charts' checks to pass, no direct pushes to main."
fi

echo "== Done =="
echo "Baseline tagged v0.1.0. Future milestones: v0.2.0 (charts+CI), v0.3.0 (multi-cloud), etc."
