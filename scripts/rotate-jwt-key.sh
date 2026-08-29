#!/usr/bin/env bash
# Rotates the Users service JWT signing key end to end:
#   1. issues a token with the CURRENT key (the "old" token)
#   2. generates a new key and updates the Kubernetes Secret
#   3. triggers a rolling restart, and continuously hits the service
#      throughout the rollout to prove zero downtime
#   4. proves the old token is now rejected
#   5. proves a freshly issued token (signed with the new key) is accepted
#
# Nothing here is a claim of success without the actual before/after token
# checks below — that's the point of this script.
set -euo pipefail

NAMESPACE="${1:-cloudcrafter}"
SECRET_NAME="users-jwt-key"
LOCAL_PORT=5001
DEMO_USER_ID="u1"

cleanup() {
  kill "${PF_PID:-}" 2>/dev/null || true
  kill "${AVAIL_PID:-}" 2>/dev/null || true
}
trap cleanup EXIT

echo "== 0. Port-forwarding users service (namespace: $NAMESPACE) =="
kubectl port-forward svc/users -n "$NAMESPACE" "$LOCAL_PORT":80 >/tmp/pf-users.log 2>&1 &
PF_PID=$!
sleep 3

BASE_URL="http://localhost:$LOCAL_PORT"

echo "== 1. Logging in with the CURRENT key to get the 'old' token =="
OLD_LOGIN=$(curl -sf -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"userId\":\"$DEMO_USER_ID\"}")
OLD_TOKEN=$(echo "$OLD_LOGIN" | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")
OLD_FPR=$(echo "$OLD_LOGIN" | python3 -c "import json,sys; print(json.load(sys.stdin)['signedWithKeyFingerprint'])")
echo "  Old token issued, signed with key fingerprint: $OLD_FPR"

echo "== 2. Confirming the old token is currently VALID (sanity check before rotation) =="
PRE_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/auth/verify" -H "Authorization: Bearer $OLD_TOKEN")
if [ "$PRE_CHECK" != "200" ]; then
  echo "  Unexpected: old token isn't valid even before rotation (HTTP $PRE_CHECK). Aborting."
  exit 1
fi
echo "  Confirmed valid (HTTP 200) — proceeding with rotation."

echo "== 3. Generating a new signing key and updating the Secret =="
NEW_KEY=$(openssl rand -hex 64)
kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=jwt-secret="$NEW_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "  Secret '$SECRET_NAME' updated."

echo "== 4. Starting a continuous availability probe (background, every 0.5s) =="
: > /tmp/rotation-availability.log
(
  fail_count=0
  total=0
  while true; do
    total=$((total + 1))
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "$BASE_URL/health" || echo "000")
    echo "$(date +%H:%M:%S) $code" >> /tmp/rotation-availability.log
    if [ "$code" != "200" ]; then
      fail_count=$((fail_count + 1))
    fi
    sleep 0.5
  done
) &
AVAIL_PID=$!

echo "== 5. Triggering a rolling restart of the users Deployment =="
kubectl rollout restart deployment/users -n "$NAMESPACE"
kubectl rollout status deployment/users -n "$NAMESPACE" --timeout=120s

echo "== 6. Stopping availability probe and checking results =="
kill "$AVAIL_PID" 2>/dev/null || true
wait "$AVAIL_PID" 2>/dev/null || true

TOTAL_CHECKS=$(wc -l < /tmp/rotation-availability.log | tr -d ' ')
FAILED_CHECKS=$(grep -vc " 200$" /tmp/rotation-availability.log || true)
echo "  Requests during rollout: $TOTAL_CHECKS, non-200 responses: $FAILED_CHECKS"
if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo "  ZERO DOWNTIME confirmed — every request during the rollout returned 200."
else
  echo "  WARNING: $FAILED_CHECKS request(s) failed during rollout. See /tmp/rotation-availability.log"
fi

echo "== 7. Confirming the OLD token is now REJECTED =="
# Reconnect port-forward in case the old forwarded pod cycled out.
kill "$PF_PID" 2>/dev/null || true
wait "$PF_PID" 2>/dev/null || true
kubectl port-forward svc/users -n "$NAMESPACE" "$LOCAL_PORT":80 >/tmp/pf-users.log 2>&1 &
PF_PID=$!
sleep 3

OLD_VERIFY=$(curl -s -w "\n%{http_code}" "$BASE_URL/auth/verify" -H "Authorization: Bearer $OLD_TOKEN")
OLD_VERIFY_CODE=$(echo "$OLD_VERIFY" | tail -n1)
OLD_VERIFY_BODY=$(echo "$OLD_VERIFY" | head -n -1)
echo "  Old token verify -> HTTP $OLD_VERIFY_CODE"
echo "  $OLD_VERIFY_BODY"
if [ "$OLD_VERIFY_CODE" = "401" ]; then
  echo "  PASS: old token correctly rejected after rotation."
else
  echo "  FAIL: old token was NOT rejected (expected 401, got $OLD_VERIFY_CODE)."
fi

echo "== 8. Confirming a NEW token (signed post-rotation) is ACCEPTED =="
NEW_LOGIN=$(curl -sf -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"userId\":\"$DEMO_USER_ID\"}")
NEW_TOKEN=$(echo "$NEW_LOGIN" | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")
NEW_FPR=$(echo "$NEW_LOGIN" | python3 -c "import json,sys; print(json.load(sys.stdin)['signedWithKeyFingerprint'])")

NEW_VERIFY=$(curl -s -w "\n%{http_code}" "$BASE_URL/auth/verify" -H "Authorization: Bearer $NEW_TOKEN")
NEW_VERIFY_CODE=$(echo "$NEW_VERIFY" | tail -n1)
NEW_VERIFY_BODY=$(echo "$NEW_VERIFY" | head -n -1)
echo "  New token (fingerprint $NEW_FPR) verify -> HTTP $NEW_VERIFY_CODE"
echo "  $NEW_VERIFY_BODY"
if [ "$NEW_VERIFY_CODE" = "200" ]; then
  echo "  PASS: new token correctly accepted."
else
  echo "  FAIL: new token was NOT accepted (expected 200, got $NEW_VERIFY_CODE)."
fi

echo ""
echo "== ROTATION SUMMARY =="
echo "  Old key fingerprint: $OLD_FPR"
echo "  New key fingerprint: $NEW_FPR"
echo "  Zero downtime:       $([ "$FAILED_CHECKS" -eq 0 ] && echo YES || echo "NO ($FAILED_CHECKS failed requests)")"
echo "  Old token rejected:  $([ "$OLD_VERIFY_CODE" = "401" ] && echo YES || echo NO)"
echo "  New token accepted:  $([ "$NEW_VERIFY_CODE" = "200" ] && echo YES || echo NO)"
