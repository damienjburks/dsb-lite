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
# The bucket/key/region are set statically below, so initialization is just:
#
#   terraform init
#
# The bucket name follows the bootstrap convention
# dsb-lite-tfstate-<account-id>; update it here if the account changes.
#
# Using an older Terraform (< 1.10)? Remove `use_lockfile` below and add a
# DynamoDB table for locking.
# ---------------------------------------------------------------------------
terraform {
  backend "s3" {
    bucket  = "dsb-lite-tfstate-083281668894"
    key     = "dsb-lite/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
