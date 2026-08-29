#!/usr/bin/env bash
# Uploads a sample ticket receipt to the LocalStack S3 bucket, which
# should automatically trigger the Lambda -> Notifications flow.
set -euo pipefail

ENDPOINT="http://localhost:4566"
BUCKET="ticket-receipts"
REGION="us-east-1"
TICKET_ID="${1:-t1}"
FILE_NAME="ticket-${TICKET_ID}-receipt.txt"
TMP_FILE="/tmp/${FILE_NAME}"

echo "Ticket ${TICKET_ID} — receipt confirmed on $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TMP_FILE"

echo "== Uploading $FILE_NAME to s3://$BUCKET/ =="
aws --endpoint-url="$ENDPOINT" --region "$REGION" s3 cp "$TMP_FILE" "s3://$BUCKET/$FILE_NAME"

echo "== Waiting a moment for the Lambda to process the event =="
sleep 3

echo "== Checking the Notifications service (make sure 'kubectl port-forward svc/notifications 3004:80 -n cloudcrafter' is running) =="
curl -s http://localhost:3004/notifications | python3 -m json.tool || true

echo ""
echo "If you see a notification above referencing '$FILE_NAME', the end-to-end event flow works."
