# Discover the account/region we are operating in.
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# Automatic discovery of the account's default VPC and its default subnets.
# The lab intentionally reuses existing default networking so we never create a
# VPC, subnets, route tables, IGW, or NAT Gateway.
# ---------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}
