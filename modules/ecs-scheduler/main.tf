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
      Resource = [var.ecs_service_arn]
    }]
  })
}

# Scale Up Schedule (09:00 KST)
resource "aws_scheduler_schedule" "scale_up" {
  name = "${var.service_name}-scale-up-${var.environment}"

  schedule_expression          = var.scale_up_cron
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode = "OFF"
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
    mode = "OFF"
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
