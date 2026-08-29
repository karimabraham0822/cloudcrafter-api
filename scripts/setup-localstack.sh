#!/usr/bin/env bash
# Sets up the S3 -> Lambda -> Notifications event flow on LocalStack.
# Requires: awscli, running LocalStack (see localstack/docker-compose.yml)
set -euo pipefail

ENDPOINT="http://localhost:4566"
BUCKET="ticket-receipts"
FUNCTION_NAME="receipt-notifier"
REGION="us-east-1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAMBDA_DIR="$ROOT_DIR/localstack/lambda"

aws_ls() {
  aws --endpoint-url="$ENDPOINT" --region "$REGION" "$@"
}

echo "== 1. Creating S3 bucket: $BUCKET =="
aws_ls s3 mb "s3://$BUCKET" || echo "(bucket may already exist, continuing)"

echo "== 2. Packaging Lambda function =="
cd "$LAMBDA_DIR"
rm -f function.zip
zip -q -r function.zip index.js
cd "$ROOT_DIR"

echo "== 3. Creating (or updating) Lambda function: $FUNCTION_NAME =="
if aws_ls lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
  aws_ls lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$LAMBDA_DIR/function.zip"
else
  aws_ls lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime nodejs18.x \
    --handler index.handler \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --zip-file "fileb://$LAMBDA_DIR/function.zip" \
    --timeout 30
fi

echo "== 4. Granting S3 permission to invoke the Lambda =="
aws_ls lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id s3invoke \
  --action "lambda:InvokeFunction" \
  --principal s3.amazonaws.com \
  --source-arn "arn:aws:s3:::$BUCKET" \
  >/dev/null 2>&1 || echo "(permission may already exist, continuing)"

echo "== 5. Wiring the S3 event notification -> Lambda =="
LAMBDA_ARN="arn:aws:lambda:$REGION:000000000000:function:$FUNCTION_NAME"

cat > /tmp/notification-config.json <<EOF
{
  "LambdaFunctionConfigurations": [
    {
      "LambdaFunctionArn": "$LAMBDA_ARN",
      "Events": ["s3:ObjectCreated:*"]
    }
  ]
}
EOF

aws_ls s3api put-bucket-notification-configuration \
  --bucket "$BUCKET" \
  --notification-configuration file:///tmp/notification-config.json

echo "== Done =="
echo "Bucket '$BUCKET' now triggers '$FUNCTION_NAME' on every upload."
echo "Next: run scripts/upload-receipt.sh to test the full flow."
