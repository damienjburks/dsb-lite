variable "aws_region" {
  description = "AWS region to deploy DSB Lite into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix and tag all resources."
  type        = string
  default     = "dsb-lite"
}

variable "environment" {
  description = "Deployment environment name (used for tagging and the APP_ENV variable)."
  type        = string
  default     = "workshop"
}

variable "container_image" {
  description = <<-EOT
    Full container image reference to deploy (e.g. <account>.dkr.ecr.<region>.amazonaws.com/dsb-lite:<sha>).
    Leave empty on the first apply; Terraform will fall back to the ECR repo URL with the `image_tag`
    tag. In steady state the GitHub Actions pipeline manages the running image, so this is mainly for
    the initial bootstrap.
  EOT
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "Image tag to deploy when `container_image` is not provided."
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 3000
}

variable "desired_count" {
  description = "Number of Fargate tasks to run."
  type        = number
  default     = 1
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
  default     = 14
}

variable "health_check_path" {
  description = "Path the ALB target group uses for health checks."
  type        = string
  default     = "/health"
}

# NOTE: GitHub OIDC / deploy-role settings (github_repository, etc.) are
# CloudFormation bootstrap parameters (../bootstrap), not Terraform variables.
