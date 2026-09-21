#!/usr/bin/env bash
# One-time bootstrap: create the S3 bucket that holds Terraform remote state.
# Run this ONCE before the first `terraform init`. It is idempotent-ish:
# it will fail loudly if the bucket name is already taken by someone else
# (S3 bucket names are globally unique — pick your own).
#
# Usage:
#   ./bootstrap-backend.sh <state-bucket-name> [region]
#
# Then set the same bucket name in backend.tf (or pass it via
# `terraform init -backend-config="bucket=<name>"`).
set -euo pipefail

BUCKET="${1:?Usage: ./bootstrap-backend.sh <state-bucket-name> [region]}"
REGION="${2:-us-east-1}"

echo "Creating state bucket s3://${BUCKET} in ${REGION}..."

if [[ "${REGION}" == "us-east-1" ]]; then
  aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}"
else
  aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"
fi

echo "Enabling versioning (lets you recover a corrupted/overwritten state)..."
aws s3api put-bucket-versioning --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

echo "Enabling default encryption..."
aws s3api put-bucket-encryption --bucket "${BUCKET}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "Blocking public access..."
aws s3api put-public-access-block --bucket "${BUCKET}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo
echo "Done. Now set this in terraform/backend.tf:"
echo "    bucket = \"${BUCKET}\""
echo "    region = \"${REGION}\""
