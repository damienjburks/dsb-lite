# DSB Lite

A hands-on AWS deployment lab for **The DevSec Blueprint**. DSB Lite is a small
Node.js/Express service that serves a single-page website, packaged as a Docker
image and deployed to **AWS ECS Fargate** behind an **internet-facing Application
Load Balancer**, all provisioned with **Terraform** and shipped by a **GitHub
Actions** pipeline that authenticates to AWS through **OIDC**.

The lab intentionally reuses your account's **default VPC and default subnets** and
assigns tasks a **public IP**, so there is no NAT Gateway, no custom domain, and no
extra networking to manage. The site is reached over **HTTP** at the
AWS-generated load balancer DNS name.

---

## Architecture

```
GitHub Actions (OIDC)
        │  build → push (tag = commit SHA)
        ▼
   Amazon ECR  ──(immutable, scan-on-push)
        │  pull
        ▼
Internet ─▶ ALB (HTTP :80) ─▶ Target Group ─▶ ECS Fargate task (public IP)
                                                    │
                                                    └─▶ CloudWatch Logs
```

- **App:** Express server (`src/server.js`) serving `public/` plus `/health` and `/api/version`.
- **Compute:** ECS Fargate service (1 task by default), deployment **circuit breaker + automatic rollback** enabled.
- **Networking:** default VPC + default subnets discovered via Terraform data sources; public IP on the task.
- **Registry:** ECR with **immutable tags** and **scan-on-push**.

---

## Repository layout

```
.
├── src/server.js              # Express app: static site + /health + /api/version
├── public/                    # Single-page website (HTML/CSS/JS)
├── Dockerfile                 # Multi-stage, distroless Chainguard image (non-root)
├── .github/workflows/
│   ├── deploy.yml             # App CI/CD: OIDC build → ECR → ECS deploy
│   └── terraform.yml          # Infra CI/CD: OIDC → terraform plan (PR) / apply (main)
├── bootstrap/                 # CloudFormation: manual, one-time prerequisites
│   └── bootstrap.yaml         # S3 state bucket + GitHub OIDC provider + deploy roles
├── terraform/                 # ECR, IAM (task roles), ALB, ECS, logs, outputs, S3 backend
└── README.md
```

---

## Prerequisites

- An AWS account with a **default VPC** in your target region (most accounts have one).
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), configured (`aws configure`)
- [Docker](https://docs.docker.com/get-docker/)
- [Node.js](https://nodejs.org/) 20+ (only needed to run the app locally)
- A GitHub repository (for the CI/CD pipeline)

> No default VPC? Create one with `aws ec2 create-default-vpc`.

---

## Run locally

```bash
npm install
npm start
# open http://localhost:3000
```

Check the endpoints:

```bash
curl http://localhost:3000/health
curl http://localhost:3000/api/version
```

Or build and run the container:

```bash
docker build -t dsb-lite:local .
docker run --rm -p 3000:3000 dsb-lite:local
```

> The image is built on [Chainguard Node images](https://images.chainguard.dev/directory/image/node/overview):
> a `-dev` variant (with npm) for the build stage and the minimal, distroless
> runtime image. It runs as the non-root `node` user (UID 65532) by default and
> has no shell, so `docker exec` into it won't drop you into a prompt — that's
> expected for a distroless image.

---

## Deploy to AWS

### 1. Deploy the bootstrap stack (manual, one time)

Some things must exist **before** Terraform runs and back the pipeline that runs
Terraform: the S3 state bucket, the GitHub OIDC provider, and the CI deploy
roles. These are managed with **CloudFormation** and deployed manually, once per
account:

```bash
aws cloudformation deploy \
  --template-file bootstrap/bootstrap.yaml \
  --stack-name dsb-lite-bootstrap \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    ProjectName=dsb-lite \
    GitHubRepository=devsecblueprint/dsb-lite \
    GitHubBranch=main

# Read the outputs you'll need below:
aws cloudformation describe-stacks --stack-name dsb-lite-bootstrap \
  --query 'Stacks[0].Outputs' --output table
```

This creates:

| Output | Meaning |
| --- | --- |
| `StateBucketName` | S3 bucket for Terraform state (versioned, encrypted, private) |
| `AppDeployRoleArn` | Role for `deploy.yml` → repo variable `AWS_ROLE_ARN` |
| `TerraformDeployRoleArn` | Role for `terraform.yml` → repo variable `TF_AWS_ROLE_ARN` |

State locking uses S3's native lockfile support (Terraform >= 1.10), so no
DynamoDB table is needed. See [`bootstrap/README.md`](bootstrap/README.md) for
details (including reusing an existing OIDC provider).

> Want purely local state instead? Delete `terraform/backend.tf` and run a plain
> `terraform init` — but you'll still need the OIDC roles from the stack for CI.

### 2. Provision infrastructure with Terraform

Initialize the S3 backend with the bucket from step 1, then apply:

Use the `StateBucketName` from the bootstrap stack as the backend bucket:

```bash
cd terraform
cp example.tfvars terraform.tfvars   # edit region / sizing if desired

BUCKET=$(aws cloudformation describe-stacks --stack-name dsb-lite-bootstrap \
  --query "Stacks[0].Outputs[?OutputKey=='StateBucketName'].OutputValue" --output text)

terraform init \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="key=dsb-lite/terraform.tfstate" \
  -backend-config="region=us-east-1"

terraform apply
```

Prefer a file? Copy `backend.hcl.example` to `backend.hcl`, fill it in, and run
`terraform init -backend-config=backend.hcl`. (`backend.hcl` is gitignored.)

Terraform prints these outputs:

| Output | Meaning |
| --- | --- |
| `ecr_repository_url` | Where images are pushed |
| `ecs_cluster_name` | ECS cluster name |
| `ecs_service_name` | ECS service name |
| `alb_dns_name` | Load balancer DNS name |
| `application_url` | Public HTTP URL of the site |

> On the first `apply` there is no image in ECR yet, so the ECS task cannot
> start until the pipeline (step 4) pushes one. This is expected. The service
> uses `latest` as a placeholder until then.

### 3. Configure GitHub Actions

In your GitHub repo, add a **repository variable** named `AWS_ROLE_ARN` set to
the `AppDeployRoleArn` output from the bootstrap stack:

`Settings → Secrets and variables → Actions → Variables → New repository variable`

If your region/names differ from the defaults, update the `env:` block at the
top of `.github/workflows/deploy.yml` to match your Terraform outputs.

### 4. Build and deploy the image

Push to `main` (or run the workflow manually from the Actions tab). The pipeline:

1. Authenticates to AWS via OIDC (no long-lived keys).
2. Builds the image and tags it with the **commit SHA**.
3. Pushes it to ECR.
4. Registers a new **ECS task-definition revision** pointing at that image.
5. Updates the ECS service and waits for it to stabilize.

Because tags are immutable and keyed to the commit SHA, every deploy is
traceable back to the exact source it was built from.

---

## CI/CD workflows

The repo ships with two GitHub Actions workflows, both authenticating to AWS via
OIDC (no long-lived keys):

| Workflow | File | Trigger | What it does |
| --- | --- | --- | --- |
| **App deploy** | `.github/workflows/deploy.yml` | push to `main`, manual | Build image → push to ECR → register task def → update ECS service |
| **Infra deploy** | `.github/workflows/terraform.yml` | changes under `terraform/**` | `plan` on PRs, `apply` on push to `main` |

### Required repository variables

Set these under `Settings → Secrets and variables → Actions → Variables`:

All three come from the **bootstrap stack outputs** (step 1):

| Variable | Used by | Bootstrap output |
| --- | --- | --- |
| `AWS_ROLE_ARN` | deploy.yml | `AppDeployRoleArn` (ECR + ECS permissions) |
| `TF_AWS_ROLE_ARN` | terraform.yml | `TerraformDeployRoleArn` (broader infra permissions) |
| `TF_STATE_BUCKET` | terraform.yml | `StateBucketName` |

> The app-deploy role is deliberately scoped to ECR + ECS. Terraform needs to
> create/modify ALB, IAM, ECS, ECR, CloudWatch, etc., so give `terraform.yml` a
> separate, broader role via `TF_AWS_ROLE_ARN`.

### Infrastructure deployment workflow

`terraform.yml` runs `fmt`, `init` (against the S3 backend), and `validate` on
every run. On a **pull request** it runs `terraform plan` and posts the plan to
the job summary for review; on **push to `main`** (or manual dispatch) it runs
`terraform apply`.

```yaml
name: Terraform Infrastructure

on:
  push:
    branches: [main]
    paths: ['terraform/**', '.github/workflows/terraform.yml']
  pull_request:
    branches: [main]
    paths: ['terraform/**', '.github/workflows/terraform.yml']
  workflow_dispatch: {}

env:
  AWS_REGION: us-east-1
  TF_STATE_KEY: dsb-lite/terraform.tfstate
  WORKING_DIR: terraform

permissions:
  id-token: write
  contents: read
  pull-requests: write

concurrency:
  group: terraform-${{ github.ref }}
  cancel-in-progress: false

jobs:
  terraform:
    name: Terraform ${{ github.event_name == 'pull_request' && 'plan' || 'apply' }}
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ${{ env.WORKING_DIR }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.TF_AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.10.5

      - name: Terraform fmt
        run: terraform fmt -check -recursive

      - name: Terraform init
        run: |
          terraform init -input=false \
            -backend-config="bucket=${{ vars.TF_STATE_BUCKET }}" \
            -backend-config="key=${TF_STATE_KEY}" \
            -backend-config="region=${AWS_REGION}"

      - name: Terraform validate
        run: terraform validate -no-color

      - name: Terraform plan
        if: github.event_name == 'pull_request'
        run: |
          set -o pipefail
          terraform plan -input=false -no-color -out=tfplan | tee plan.txt

      - name: Publish plan to summary
        if: github.event_name == 'pull_request'
        run: |
          {
            echo '### Terraform Plan 📖';
            echo '';
            echo '```terraform';
            tail -c 60000 plan.txt;
            echo '```';
          } >> "$GITHUB_STEP_SUMMARY"

      - name: Terraform apply
        if: github.event_name == 'push' || github.event_name == 'workflow_dispatch'
        run: terraform apply -input=false -auto-approve
```

> This workflow expects the S3 backend and OIDC roles to already exist. Deploy
> the CloudFormation bootstrap stack once first (see step 1) and set
> `TF_STATE_BUCKET` / `TF_AWS_ROLE_ARN` to its outputs.

---

## Validate the deployment

```bash
cd terraform
URL="$(terraform output -raw application_url)"

curl -i "$URL/health"          # → 200, {"status":"ok",...}
curl -s "$URL/api/version"     # → version, environment, buildTime, gitCommit
open "$URL"                     # (macOS) open the site in a browser
```

The footer of the site shows the running version, environment, and short commit
SHA pulled live from `/api/version`. After a deploy, confirm the `gitCommit`
matches the commit you just shipped.

Watch the rollout:

```bash
aws ecs describe-services \
  --cluster "$(terraform output -raw ecs_cluster_name)" \
  --services "$(terraform output -raw ecs_service_name)" \
  --query 'services[0].deployments'
```

---

## Troubleshooting

**Tasks keep restarting / target group unhealthy**
- Confirm the container listens on the port the target group checks (`3000` / `/health`).
- Check container logs: CloudWatch Logs group `/ecs/dsb-lite`.
- Ensure the service security group allows inbound from the ALB security group.

**Tasks stuck in PENDING or can't pull the image**
- The task needs a public IP to reach ECR without a NAT Gateway — this is set
  (`assign_public_ip = true`). Verify the subnets used are the default (public) subnets.
- Confirm an image actually exists in ECR (the first deploy must have run).

**Deployment fails and rolls back automatically**
- That's the **circuit breaker** doing its job. New tasks failed health checks,
  so ECS reverted to the last healthy task definition. Inspect CloudWatch Logs
  and the failed deployment's stopped-task reason.

**GitHub Actions: `Not authorized to perform sts:AssumeRoleWithWebIdentity`**
- Confirm `AWS_ROLE_ARN` / `TF_AWS_ROLE_ARN` match the bootstrap stack outputs.
- Confirm `GitHubRepository`/`GitHubBranch` in the bootstrap stack match the repo
  and branch the workflow runs from.
- Confirm the workflow has `permissions: id-token: write`.

**`RegisterTaskDefinition` errors about unexpected fields**
- The workflow strips read-only fields with `jq` before re-registering. If you
  customized the task definition, keep that step intact.

**ECR push denied**
- The image tag already exists (tags are **immutable**). Since tags are the
  commit SHA, this only happens if you re-run a deploy for an unchanged commit.

---

## Cleanup

Tear everything down when the workshop ends:

```bash
cd terraform
terraform destroy
```

The ECR repository uses `force_delete = true`, so it removes any images along
with it. CloudWatch log groups are deleted by Terraform as well. Verify nothing
is left running:

```bash
aws ecs list-services --cluster dsb-lite-cluster
aws elbv2 describe-load-balancers --names dsb-lite-alb
```

The bootstrap stack (state bucket, OIDC provider, deploy roles) is separate and
**not** removed by `terraform destroy`. The state bucket also has a `Retain`
deletion policy so it survives stack deletion. To remove the bootstrap resources,
empty and delete the state bucket, then delete the stack:

```bash
aws cloudformation delete-stack --stack-name dsb-lite-bootstrap
```

---

## Notes on scope

By design this lab does **not** create a VPC, subnets, route tables, internet
gateway, NAT gateway, custom domain, TLS certificate, database, authentication
system, or external API integration. It focuses on the container build and the
ECR → ECS → ALB deployment path using existing default networking.

---

## About The DevSec Blueprint

The DevSec Blueprint is a free, open learning platform for practical DevSecOps
and cloud security skills. Structured DevSecOps and Cloud Security mastery,
built through real systems, not theory.

- Website: https://devsecblueprint.com
- GitHub: https://github.com/devsecblueprint/devsecblueprint
- Discord: https://discord.gg/SkYECC4TD8
- LinkedIn: https://www.linkedin.com/company/devsecblueprint
- X / Twitter: https://x.com/devsecblueprint
- Instagram: https://www.instagram.com/devsecblueprint

## License

MIT
