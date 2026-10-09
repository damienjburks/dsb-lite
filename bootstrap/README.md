# DSB Lite — Bootstrap (CloudFormation)

These are the prerequisites that must exist **before** Terraform runs, so they
are managed with CloudFormation and deployed **manually, once per account** —
not by Terraform (which depends on them) or by the CI pipeline (which uses them).

`bootstrap.yaml` creates:

- **S3 bucket** for Terraform remote state (versioned, encrypted, private)
- **GitHub OIDC provider** (`token.actions.githubusercontent.com`)
- **App-deploy role** (`dsb-lite-github-deploy`) — ECR push + ECS deploy, used by `deploy.yml`
- **Terraform-deploy role** (`dsb-lite-github-terraform`) — infra permissions, used by `terraform.yml`

## GitHub OIDC trust (our org only)

Trust is scoped to the **`devsecblueprint`** org and nothing else — any repo,
branch, and event under it can assume the deploy roles. One pattern does it, with
the org's immutable numeric ID pinned:

```
repo:devsecblueprint@156617339/*
```

Why pin the ID: GitHub's 2026-07-15 subject format embeds the org's permanent
numeric ID (`repo:devsecblueprint@156617339/dsb-lite@1412240746:...`). Matching
on that ID — not just the `devsecblueprint` slug — is what keeps a renamed or
look-alike org from assuming the role. The trailing `/*` allows every repo,
branch, and event within the org.

Look up the ID with:

```bash
gh api /orgs/devsecblueprint --jq .id   # -> 156617339
```

> If `devsecblueprint` is a user account rather than an org, use
> `gh api /users/devsecblueprint --jq .id`.

## Deploy

`aws cloudformation deploy` always works through a changeset. By passing
`--no-execute-changeset` it **creates** the changeset and stops, so you can
review exactly what will change before anything is applied — then execute it.

```bash
aws cloudformation deploy \
  --template-file bootstrap/bootstrap.yaml \
  --stack-name dsb-lite-bootstrap \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM \
  --no-execute-changeset \
  --parameter-overrides \
    ProjectName=dsb-lite \
    GitHubOrg=devsecblueprint \
    GitHubOrgId=156617339 \
    CreateOIDCProvider=true
```

The command prints a ready-to-run `aws cloudformation execute-change-set`
line (with the changeset ARN). Review the changeset first:

```bash
# List changesets for the stack to grab the latest name/ARN
aws cloudformation list-change-sets --stack-name dsb-lite-bootstrap \
  --query 'Summaries[].{Name:ChangeSetName,Status:Status,Created:CreationTime}' \
  --output table

# Inspect the actions it will take (Add / Modify / Remove)
aws cloudformation describe-change-set \
  --stack-name dsb-lite-bootstrap \
  --change-set-name <CHANGESET_NAME_OR_ARN> \
  --query 'Changes[].ResourceChange.{Action:Action,Type:ResourceType,Id:LogicalResourceId,Replace:Replacement}' \
  --output table
```

Then apply it:

```bash
aws cloudformation execute-change-set \
  --stack-name dsb-lite-bootstrap \
  --change-set-name <CHANGESET_NAME_OR_ARN>
```

> Already have the GitHub OIDC provider in this account? Add
> `CreateOIDCProvider=false` to `--parameter-overrides` so the stack reuses it
> instead of trying to create a duplicate.
>
> Want the old apply-immediately behavior for a quick first create? Drop
> `--no-execute-changeset` and the stack deploys without the review step.

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

## Verify the OIDC trust policy

Confirm the deployed role trusts only our org (`repo:devsecblueprint@156617339/*`):

```bash
aws iam get-role --role-name dsb-lite-github-deploy \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringLike' \
  --output json
```

## Tear down

The state bucket uses `DeletionPolicy: Delete`, so deleting the stack removes
**every** resource it created — including the Terraform state bucket. This keeps
re-deploys clean (no orphaned bucket to collide with), but it is destructive.

> **⚠️ The state bucket holds your Terraform remote state.** Deleting it destroys
> the record of all Terraform-managed infrastructure (ECS, ALB, ECR, IAM, logs).
> Back it up first if you might need it:
> ```bash
> aws s3 cp \
>   "s3://dsb-lite-tfstate-$(aws sts get-caller-identity --query Account --output text)/dsb-lite/terraform.tfstate" \
>   ./terraform.tfstate.backup
> ```

CloudFormation can only delete an **empty** bucket, and this one is versioned, so
purge all object versions and delete markers before deleting the stack:

```bash
BUCKET="dsb-lite-tfstate-$(aws sts get-caller-identity --query Account --output text)"

# Delete all object versions
aws s3api list-object-versions --bucket "$BUCKET" \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json \
  | aws s3api delete-objects --bucket "$BUCKET" --delete file:///dev/stdin

# Delete all delete markers
aws s3api list-object-versions --bucket "$BUCKET" \
  --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json \
  | aws s3api delete-objects --bucket "$BUCKET" --delete file:///dev/stdin

# Now the stack delete can remove the (empty) bucket along with everything else
aws cloudformation delete-stack --stack-name dsb-lite-bootstrap
aws cloudformation wait stack-delete-complete --stack-name dsb-lite-bootstrap
```

> If a `delete-objects` call reports an empty-parameter error, the bucket already
> had nothing of that kind to remove — safe to continue.
