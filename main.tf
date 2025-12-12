terraform {
  cloud {
    organization = "YOUR_ORGANIZATION_NAME"

    workspaces {
      name = "YOUR_WORKSPACE_NAME"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Common Infrastructure for Slack Notifications
resource "aws_sns_topic" "ecs_scheduler_alerts" {
  name = "ecs-scheduler-alerts-${var.environment}"

  tags = {
    Environment = var.environment
  }
}

# Lambda for Slack notifications
data "archive_file" "slack_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/slack_notifier.zip"

  source_dir = "${path.module}/slack-notifier"
}

resource "aws_lambda_function" "slack_notifier" {
  filename         = data.archive_file.slack_lambda_zip.output_path
  function_name    = "ecs-scheduler-slack-notifier-${var.environment}"
  role             = aws_iam_role.slack_lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  timeout          = 10
  source_code_hash = data.archive_file.slack_lambda_zip.output_base64sha256

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role" "slack_lambda_role" {
  name = "ecs-slack-notifier-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "slack_lambda_basic" {
  role       = aws_iam_role.slack_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_sns_topic_subscription" "slack_subscription" {
  topic_arn = aws_sns_topic.ecs_scheduler_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier.arn
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.ecs_scheduler_alerts.arn
}

# EventBridge Rule for Scheduler state changes
resource "aws_cloudwatch_event_rule" "scheduler_state_change" {
  name        = "ecs-scheduler-state-change-${var.environment}"
  description = "Capture ECS Scheduler execution results"

  event_pattern = jsonencode({
    source      = ["aws.scheduler"]
    detail-type = ["Scheduler Execution State Change"]
  })
}

resource "aws_cloudwatch_event_target" "send_to_sns" {
  rule      = aws_cloudwatch_event_rule.scheduler_state_change.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.ecs_scheduler_alerts.arn
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.ecs_scheduler_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action   = "SNS:Publish"
      Resource = aws_sns_topic.ecs_scheduler_alerts.arn
    }]
  })
}

# ============================================
# Create Schedulers per ECS Service
# ============================================

# 1. api-service
module "api_scheduler" {
  source = "./modules/ecs-scheduler"

  service_name    = "api-service-dev"
  cluster_name    = aws_ecs_cluster.app-cluster-dev.name
  ecs_service_arn = aws_ecs_service.api-service-dev.id
  environment     = var.environment

  scale_up_cron   = "cron(0 0 ? * MON-FRI *)"  # 09:00 KST
  scale_down_cron = "cron(0 9 ? * MON-FRI *)"  # 18:00 KST
}

# 2. backend-service
module "backend_scheduler" {
  source = "./modules/ecs-scheduler"

  service_name    = "backend-service-dev"
  cluster_name    = aws_ecs_cluster.app-cluster-dev.name
  ecs_service_arn = aws_ecs_service.backend-service-dev.id
  environment     = var.environment
}

# 3. worker-service(example)
module "worker_scheduler" {
  source = "./modules/ecs-scheduler"

  service_name    = "worker-service-dev"
  cluster_name    = aws_ecs_cluster.app-cluster-dev.name
  ecs_service_arn = aws_ecs_service.worker-service-dev.id
  environment     = var.environment
}

# ... Add remaining services similarly
