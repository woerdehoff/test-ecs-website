terraform {
  # Remote state in S3 (no DynamoDB lock table — this is a test setup).
  #
  # The bucket must exist BEFORE `terraform init`. Create it once with
  # terraform/bootstrap-backend.sh, then fill in the bucket name below
  # (or pass it at init time via `-backend-config="bucket=..."`).
  backend "s3" {
    bucket  = "REPLACE_WITH_YOUR_STATE_BUCKET"
    key     = "test-ecs-website/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
