# Data sources for automatic ARN generation
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  ecs_service_arn = "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${var.cluster_name}/${var.service_name}"
}

# IAM Role for Scheduler
resource "aws_iam_role" "ecs_scheduler_role" {
  name = "${var.service_name}-scheduler-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "scheduler.amazonaws.com"
      }
    }]
  })

  tags = {
    Environment = var.environment
    Service     = var.service_name
  }
}

resource "aws_iam_role_policy" "ecs_scheduler_policy" {
  name = "${var.service_name}-scheduler-policy-${var.environment}"
  role = aws_iam_role.ecs_scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ecs:UpdateService"]
      Resource = [local.ecs_service_arn]
    }]
  })
}

# Scale Up Schedule (09:00 KST)
resource "aws_scheduler_schedule" "scale_up" {
  name = "${var.service_name}-scale-up-${var.environment}"

  schedule_expression          = var.scale_up_cron
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode                      = var.flexible_time_window_minutes > 0 ? "FLEXIBLE" : "OFF"
    maximum_window_in_minutes = var.flexible_time_window_minutes > 0 ? var.flexible_time_window_minutes : null
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
    role_arn = aws_iam_role.ecs_scheduler_role.arn

    input = jsonencode({
      Cluster      = var.cluster_name
      Service      = var.service_name
      DesiredCount = var.scale_up_count
    })
  }
}

# Scale Down Schedule (18:00 KST)
resource "aws_scheduler_schedule" "scale_down" {
  name = "${var.service_name}-scale-down-${var.environment}"

  schedule_expression          = var.scale_down_cron
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode                      = var.flexible_time_window_minutes > 0 ? "FLEXIBLE" : "OFF"
    maximum_window_in_minutes = var.flexible_time_window_minutes > 0 ? var.flexible_time_window_minutes : null
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
    role_arn = aws_iam_role.ecs_scheduler_role.arn

    input = jsonencode({
      Cluster      = var.cluster_name
      Service      = var.service_name
      DesiredCount = var.scale_down_count
    })
  }
}
