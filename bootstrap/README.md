# DSB Lite — Bootstrap (CloudFormation)

These are the prerequisites that must exist **before** Terraform runs, so they
are managed with CloudFormation and deployed **manually, once per account** —
not by Terraform (which depends on them) or by the CI pipeline (which uses them).

`bootstrap.yaml` creates:

- **S3 bucket** for Terraform remote state (versioned, encrypted, private)
- **GitHub OIDC provider** (`token.actions.githubusercontent.com`)
- **App-deploy role** (`dsb-lite-github-deploy`) — ECR push + ECS deploy, used by `deploy.yml`
- **Terraform-deploy role** (`dsb-lite-github-terraform`) — infra permissions, used by `terraform.yml`

## Deploy

```bash
aws cloudformation deploy \
  --template-file bootstrap/bootstrap.yaml \
  --stack-name dsb-lite-bootstrap \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    ProjectName=dsb-lite \
    GitHubRepository=devsecblueprint/dsb-lite \
    GitHubBranch=main
```

> Already have the GitHub OIDC provider in this account? Add
> `CreateOIDCProvider=false` to `--parameter-overrides` so the stack reuses it
> instead of trying to create a duplicate.

## Get the outputs

```bash
aws cloudformation describe-stacks \
  --stack-name dsb-lite-bootstrap \
  --query 'Stacks[0].Outputs' --output table
```

Use them like this:

| Output | Where it goes |
| --- | --- |
| `StateBucketName` | `terraform init -backend-config="bucket=..."` and repo var `TF_STATE_BUCKET` |
| `AppDeployRoleArn` | repo variable `AWS_ROLE_ARN` (for `deploy.yml`) |
| `TerraformDeployRoleArn` | repo variable `TF_AWS_ROLE_ARN` (for `terraform.yml`) |

## Tear down

The state bucket has `DeletionPolicy: Retain`, so deleting the stack leaves it in
place (it holds your Terraform state). To remove everything, first empty and
delete the bucket, then:

```bash
aws cloudformation delete-stack --stack-name dsb-lite-bootstrap
```
