# SNS Topic for ECS Scheduler Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts-${var.environment}"

  tags = {
    Environment = var.environment
  }
}

# Lambda Function for Slack Notifications
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"
  source_dir  = "${path.module}/lambda"
}

resource "aws_lambda_function" "slack_notifier" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.name_prefix}-slack-notifier-${var.environment}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  timeout          = 10
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }

  tags = {
    Environment = var.environment
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.name_prefix}-slack-notifier-role-${var.environment}"

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

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SNS Subscription for Lambda
resource "aws_sns_topic_subscription" "slack" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier.arn
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

# EventBridge Rule for ECS UpdateService via CloudTrail
resource "aws_cloudwatch_event_rule" "ecs_update_service" {
  name        = "${var.name_prefix}-update-service-${var.environment}"
  description = "Capture ECS UpdateService calls from Scheduler"

  event_pattern = jsonencode({
    source      = ["aws.ecs"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["UpdateService"]
    }
  })
}

resource "aws_cloudwatch_event_target" "send_to_sns" {
  rule      = aws_cloudwatch_event_rule.ecs_update_service.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.alerts.arn
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action   = "SNS:Publish"
      Resource = aws_sns_topic.alerts.arn
    }]
  })
}
