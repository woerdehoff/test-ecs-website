# test-ecs-website

A minimal static website (nginx) deployed to **AWS ECS Fargate**, with
infrastructure defined in **Terraform** and deployment driven by **Jenkins**
from this GitHub repo.

```
app/            # the website + Dockerfile (nginx serving index.html)
terraform/      # all AWS infra (VPC, ALB, ECR, ECS cluster/service, IAM)
Jenkinsfile     # CI/CD pipeline: build image -> push to ECR -> terraform apply
```

## Architecture

```
Internet ──▶ ALB (:80) ──▶ Target Group ──▶ ECS Fargate task (nginx :80)
                                              │
                                              └── image pulled from ECR
```

- **VPC** with 2 public subnets across AZs, internet gateway, public route table.
- **ALB** (internet-facing) forwards HTTP :80 to the Fargate service.
- **ECS Fargate** service (1 task by default) running the nginx container.
- **ECR** repository holds the image, tagged with the git commit SHA.
- Terraform **state in S3** (no DynamoDB lock table — this is a test setup).

## One-time setup

### Terraform state bucket — handled automatically

The state bucket does **not** need to be created by hand. The Jenkins pipeline
has an **"Ensure Terraform state bucket"** stage that creates it (with
versioning, encryption, and public access blocked) if it doesn't exist. The
bucket name is derived deterministically from your AWS account ID:
`test-ecs-website-tfstate-<ACCOUNT_ID>`, and passed to `terraform init` via
`-backend-config`.

For **local** runs (no Jenkins), either run `terraform/bootstrap-backend.sh
<bucket> us-east-1` once, or just create the bucket and pass it at init time —
see "Deploying manually" below.

### Jenkins prerequisites

The Jenkins agent needs:

- **Docker** available to the build user.
- **Terraform** >= 1.5 and the **AWS CLI v2** on `PATH`.
- **AWS credentials** with permissions for ECR, ECS, EC2/VPC, ELB, IAM, S3,
  and CloudWatch Logs. Provide them however your Jenkins is set up — an
  instance profile on the agent, or the AWS Credentials plugin. (This repo's
  `Jenkinsfile` assumes the environment already has credentials; add a
  `withAWS(...)` / `withCredentials(...)` wrapper if you use the plugin.)
- A **Pipeline job** pointing at this repo, using `Jenkinsfile` from SCM.

## How the pipeline works (`Jenkinsfile`)

1. **Checkout** the repo.
2. **Resolve ECR & login** — derive the registry URL from the account ID and
   `docker login` to ECR.
3. **Ensure ECR repo** — `terraform apply -target=aws_ecr_repository.main`.
   This solves the first-run chicken-and-egg problem (you can't push an image
   to a repo that doesn't exist yet). No-op on later runs.
4. **Build & push image** — tagged with the short git SHA (and `latest`).
5. **Terraform apply** — full apply with `-var image_tag=<sha>`, which updates
   the ECS task definition and rolls out a new deployment.
6. **Show URL** — prints the public `website_url`.

Because there's no state lock table, concurrent builds are disabled
(`disableConcurrentBuilds()`).

## Deploying manually (without Jenkins)

```bash
# from repo root, with AWS creds + docker available:
cd terraform
BUCKET="test-ecs-website-tfstate-$(aws sts get-caller-identity --query Account --output text)"
# create the state bucket once (skip if it already exists):
./bootstrap-backend.sh "$BUCKET" us-east-1
terraform init -backend-config="bucket=$BUCKET"
terraform apply -target=aws_ecr_repository.main -auto-approve

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REPO=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/test-ecs-website
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

TAG=$(git rev-parse --short HEAD)
docker build -t $REPO:$TAG ../app
docker push $REPO:$TAG

terraform apply -var="image_tag=$TAG" -auto-approve
terraform output -raw website_url
```

Open the printed URL — you should see the "Hello from AWS ECS" page.

## Tear down

```bash
cd terraform
terraform destroy
```

(The ECR repo uses `force_delete = true`, so images won't block destroy.)
The S3 state bucket is not managed by Terraform; delete it manually if you no
longer need the state.

## Configuration

Common variables (see `terraform/variables.tf`):

| Variable         | Default            | Purpose                          |
|------------------|--------------------|----------------------------------|
| `aws_region`     | `us-east-1`        | Region to deploy into            |
| `project_name`   | `test-ecs-website` | Name prefix for resources        |
| `image_tag`      | `latest`           | Image tag to deploy (CI: git SHA)|
| `desired_count`  | `1`                | Number of Fargate tasks          |
| `task_cpu`       | `256`              | Task CPU units (256 = 0.25 vCPU) |
| `task_memory`    | `512`              | Task memory (MiB)                |
