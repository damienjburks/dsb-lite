# CloudWatch Log group for the ECS task's container logs.
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.log_retention_days
}
