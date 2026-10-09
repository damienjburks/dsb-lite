# ---------------------------------------------------------------------------
# Internet-facing Application Load Balancer deployed across the default subnets.
# ---------------------------------------------------------------------------
resource "aws_lb" "app" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids

  # Keeps `terraform destroy` frictionless for a workshop environment.
  enable_deletion_protection = false
}

# Target group for the Fargate tasks. `target_type = "ip"` is required for
# awsvpc-mode Fargate tasks.
resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # Allow connections to drain quickly on deploy/rollback in the lab.
  deregistration_delay = 30
}

# HTTP listener on port 80. The project uses plain HTTP through the
# AWS-generated ALB DNS name because there is no registered domain / TLS cert.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
