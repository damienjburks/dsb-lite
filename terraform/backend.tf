# ---------------------------------------------------------------------------
# Remote state backend (Amazon S3).
#
# Terraform state is stored in an S3 bucket so it is durable, shared, and safe
# for team/CI use instead of living on one laptop. State locking uses S3's
# native lockfile support (`use_lockfile`, Terraform >= 1.10), so no DynamoDB
# table is required.
#
# CHICKEN-AND-EGG: the bucket must exist BEFORE this backend can be used.
# It is created by the CloudFormation bootstrap stack (../bootstrap/bootstrap.yaml),
# which you deploy manually once per account. Use its StateBucketName output as
# the backend `bucket`, then initialize this backend.
#
# The bucket/key/region are intentionally left out of this block and supplied
# at init time so the same config works across accounts. Initialize with:
#
#   terraform init \
#     -backend-config="bucket=dsb-lite-tfstate-<your-account-id>" \
#     -backend-config="key=dsb-lite/terraform.tfstate" \
#     -backend-config="region=us-east-1"
#
# Or copy backend.hcl.example to backend.hcl, fill it in, and run:
#
#   terraform init -backend-config=backend.hcl
#
# Using an older Terraform (< 1.10)? Remove `use_lockfile` below and add a
# DynamoDB table for locking via -backend-config="dynamodb_table=<name>".
# ---------------------------------------------------------------------------
terraform {
  backend "s3" {
    encrypt      = true
    use_lockfile = true
    # bucket / key / region are provided via -backend-config (see above).
  }
}
