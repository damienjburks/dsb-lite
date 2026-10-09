# ---------------------------------------------------------------------------
# Amazon ECR repository for the DSB Lite container image.
# - Image scanning on push is enabled.
# - Tags are IMMUTABLE so a given tag (e.g. a commit SHA) can never be
#   overwritten, which keeps deployments auditable and reproducible.
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep the repository tidy: expire untagged images and cap the number of tagged
# images we retain so the lab does not accumulate cost over time.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the 10 most recent tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
