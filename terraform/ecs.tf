# ---------------------------------------------------------------------------
# ECS cluster (Fargate) with Container Insights enabled.
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# ---------------------------------------------------------------------------
# Task definition.
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "app" {
  family                   = local.name_prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = local.name_prefix
      image     = local.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "APP_ENV", value = var.environment },
        { name = "PORT", value = tostring(var.container_port) }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "node -e \"require('http').get('http://127.0.0.1:'+(process.env.PORT||3000)+'/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))\""]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  # The CI pipeline registers new revisions on every deploy. Ignore image/tag
  # drift here so `terraform apply` does not fight the pipeline's revisions.
  lifecycle {
    ignore_changes = [container_definitions]
  }
}

# ---------------------------------------------------------------------------
# ECS service running on Fargate behind the ALB.
# - Public IP is assigned so tasks in the default (public) subnets can pull
#   images without a NAT Gateway.
# - Deployment circuit breaker with automatic rollback is enabled: a failed
#   deployment is rolled back to the last healthy task definition.
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "app" {
  name            = "${local.name_prefix}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = local.name_prefix
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Give tasks time to pass health checks before the ALB counts them.
  health_check_grace_period_seconds = 60

  # The pipeline updates the running task definition out-of-band, so ignore
  # changes to task_definition and desired_count to avoid apply-time churn.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http]
}
