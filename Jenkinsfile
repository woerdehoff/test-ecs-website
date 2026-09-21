pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds() // no state locking (S3-only), so serialize runs
  }

  environment {
    AWS_REGION   = 'us-east-1'
    PROJECT      = 'test-ecs-website'
    // Short git SHA — reproducible, immutable image tag per commit.
    IMAGE_TAG    = "${env.GIT_COMMIT?.take(7) ?: 'manual'}"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Resolve ECR & login') {
      steps {
        script {
          env.ACCOUNT_ID       = sh(script: "aws sts get-caller-identity --query Account --output text", returnStdout: true).trim()
          env.ECR_REGISTRY     = "${env.ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
          env.ECR_REPO         = "${env.ECR_REGISTRY}/${env.PROJECT}"
          // Globally-unique, deterministic state bucket name per account.
          env.TF_BACKEND_BUCKET = "${env.PROJECT}-tfstate-${env.ACCOUNT_ID}"
        }
        sh '''
          aws ecr get-login-password --region "$AWS_REGION" \
            | docker login --username AWS --password-stdin "$ECR_REGISTRY"
        '''
      }
    }

    // The S3 backend bucket must exist before `terraform init`. Create it
    // (with versioning, encryption, and public access blocked) if missing.
    // Idempotent: a no-op once the bucket exists. Assumes us-east-1 — for
    // other regions add --create-bucket-configuration LocationConstraint=...
    stage('Ensure Terraform state bucket') {
      steps {
        sh '''
          if aws s3api head-bucket --bucket "$TF_BACKEND_BUCKET" 2>/dev/null; then
            echo "State bucket $TF_BACKEND_BUCKET already exists."
          else
            echo "Creating state bucket $TF_BACKEND_BUCKET ..."
            aws s3api create-bucket --bucket "$TF_BACKEND_BUCKET" --region "$AWS_REGION"
            aws s3api put-bucket-versioning --bucket "$TF_BACKEND_BUCKET" \
              --versioning-configuration Status=Enabled
            aws s3api put-bucket-encryption --bucket "$TF_BACKEND_BUCKET" \
              --server-side-encryption-configuration \
              '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
            aws s3api put-public-access-block --bucket "$TF_BACKEND_BUCKET" \
              --public-access-block-configuration \
              BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
          fi
        '''
      }
    }

    // First run: the ECR repo does not exist yet, so create just the repo
    // before we try to push. On later runs this is a no-op.
    stage('Ensure ECR repo (targeted apply)') {
      steps {
        dir('terraform') {
          sh '''
            terraform init -input=false \
              -backend-config="bucket=$TF_BACKEND_BUCKET"
            terraform apply -input=false -auto-approve \
              -target=aws_ecr_repository.main
          '''
        }
      }
    }

    stage('Build & push image') {
      steps {
        dir('app') {
          sh '''
            docker build -t "$ECR_REPO:$IMAGE_TAG" -t "$ECR_REPO:latest" .
            docker push "$ECR_REPO:$IMAGE_TAG"
            docker push "$ECR_REPO:latest"
          '''
        }
      }
    }

    stage('Terraform apply (deploy)') {
      steps {
        dir('terraform') {
          sh '''
            terraform apply -input=false -auto-approve \
              -var="image_tag=$IMAGE_TAG"
          '''
        }
      }
    }

    stage('Show URL') {
      steps {
        dir('terraform') {
          sh 'terraform output -raw website_url'
        }
      }
    }
  }

  post {
    always {
      // Clean up local images so the agent disk does not fill up.
      sh 'docker image prune -f || true'
    }
  }
}
