# Copy this file to terraform.tfvars and adjust as needed.
# terraform.tfvars is gitignored so your values stay local.

aws_region   = "us-east-1"
project_name = "dsb-lite"
environment  = "workshop"

# GitHub OIDC / deploy roles live in the CloudFormation bootstrap stack
# (../bootstrap), so no GitHub settings are needed here.

# Fargate sizing (defaults are fine for the workshop).
desired_count = 1
task_cpu      = 256
task_memory   = 512
