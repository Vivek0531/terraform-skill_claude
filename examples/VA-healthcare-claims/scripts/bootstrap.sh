#!/usr/bin/env bash
# bootstrap.sh — create S3 state bucket + DynamoDB lock table before first terragrunt apply
set -euo pipefail

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
STATE_BUCKET="payments-api-tfstate-${ACCOUNT_ID}"
LOCK_TABLE="payments-api-tf-locks"

echo "==> Bootstrapping Terraform state backend"
echo "    Account: ${ACCOUNT_ID}"
echo "    Region:  ${REGION}"
echo "    Bucket:  ${STATE_BUCKET}"
echo "    Table:   ${LOCK_TABLE}"

# S3 bucket
if aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
  echo "==> S3 bucket already exists"
else
  echo "==> Creating S3 bucket..."
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${STATE_BUCKET}" --region "${REGION}"
  else
    aws s3api create-bucket --bucket "${STATE_BUCKET}" --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi
  aws s3api put-bucket-versioning --bucket "${STATE_BUCKET}" \
    --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption --bucket "${STATE_BUCKET}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  aws s3api put-public-access-block --bucket "${STATE_BUCKET}" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
  echo "==> S3 bucket created"
fi

# DynamoDB lock table
if aws dynamodb describe-table --table-name "${LOCK_TABLE}" --region "${REGION}" 2>/dev/null; then
  echo "==> DynamoDB table already exists"
else
  echo "==> Creating DynamoDB lock table..."
  aws dynamodb create-table \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"
  aws dynamodb wait table-exists --table-name "${LOCK_TABLE}" --region "${REGION}"
  echo "==> DynamoDB table created"
fi

echo ""
echo "Bootstrap complete. You can now run:"
echo "  cd terragrunt/live/aws/eks && terragrunt init && terragrunt plan"
