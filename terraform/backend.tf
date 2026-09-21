terraform {
  # Remote state in S3 (no DynamoDB lock table — this is a test setup).
  #
  # Partial backend config: the bucket name is supplied at init time via
  #   terraform init -backend-config="bucket=<name>"
  # The Jenkinsfile derives the name from the AWS account ID and creates the
  # bucket if it doesn't exist yet (see the "Ensure Terraform state bucket"
  # stage). For local runs, pass -backend-config or use bootstrap-backend.sh.
  backend "s3" {
    key     = "test-ecs-website/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
