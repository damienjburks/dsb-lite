output "ecr_repository_url" {
  description = "URL of the ECR repository for the DSB Lite image."
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository."
  value       = aws_ecr_repository.app.name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.app.name
}

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer."
  value       = aws_lb.app.dns_name
}

output "application_url" {
  description = "Public HTTP URL for the DSB Lite site."
  value       = "http://${aws_lb.app.dns_name}"
}

# NOTE: The GitHub deploy/terraform role ARNs and the state bucket name are
# outputs of the CloudFormation bootstrap stack (../bootstrap), not Terraform.
