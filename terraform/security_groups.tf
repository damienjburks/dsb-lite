# ---------------------------------------------------------------------------
# Security group for the internet-facing ALB: allow inbound HTTP from anywhere.
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "Allow inbound HTTP to the DSB Lite ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-alb" }
}

# ---------------------------------------------------------------------------
# Security group for the ECS tasks: only accept traffic from the ALB on the
# container port. Egress open so the task can pull images / reach AWS APIs.
# ---------------------------------------------------------------------------
resource "aws_security_group" "service" {
  name        = "${local.name_prefix}-service"
  description = "Allow inbound from the ALB to the DSB Lite tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "App traffic from the ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-service" }
}
