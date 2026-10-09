locals {
  name_prefix = var.project_name

  # ECR repository URL for the app image.
  ecr_repository_url = aws_ecr_repository.app.repository_url

  # Resolve the image to deploy: prefer an explicit `container_image`, otherwise
  # build it from the ECR repo URL and `image_tag`.
  container_image = var.container_image != "" ? var.container_image : "${aws_ecr_repository.app.repository_url}:${var.image_tag}"

  # Default subnets discovered from the default VPC.
  subnet_ids = data.aws_subnets.default.ids
}
