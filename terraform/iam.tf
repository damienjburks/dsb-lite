# ---------------------------------------------------------------------------
# ECS task execution role: used by the ECS agent to pull the image from ECR and
# write logs to CloudWatch. This is the AWS-managed baseline.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.name_prefix}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------------------
# ECS task role: the identity the application code runs as. DSB Lite calls no
# AWS APIs, so this role has no attached policies (least privilege). It exists
# so the app has its own distinct identity, separate from the execution role.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# ---------------------------------------------------------------------------
# NOTE: The GitHub Actions OIDC provider and the CI deploy roles are NOT
# managed here. They are bootstrap prerequisites (they must exist before
# Terraform runs and they back the pipeline that runs Terraform), so they live
# in the manually-deployed CloudFormation stack at ../bootstrap/bootstrap.yaml.
# ---------------------------------------------------------------------------
