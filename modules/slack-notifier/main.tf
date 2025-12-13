# SQS Queue for batching ECS events
resource "aws_sqs_queue" "alerts" {
  name                       = "${var.name_prefix}-alerts-${var.environment}"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 3600 # 1 hour
  receive_wait_time_seconds  = 0

  tags = {
    Environment = var.environment
  }
}

# SQS Queue Policy to allow EventBridge
resource "aws_sqs_queue_policy" "allow_eventbridge" {
  queue_url = aws_sqs_queue.alerts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.alerts.arn
    }]
  })
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
  timeout          = 30
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      ENVIRONMENT       = var.environment
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

# IAM Policy for Lambda to read from SQS
resource "aws_iam_role_policy" "lambda_sqs" {
  name = "${var.name_prefix}-lambda-sqs-${var.environment}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ]
      Resource = aws_sqs_queue.alerts.arn
    }]
  })
}

# Lambda Event Source Mapping for SQS (Batch Processing)
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn                   = aws_sqs_queue.alerts.arn
  function_name                      = aws_lambda_function.slack_notifier.arn
  batch_size                         = var.batch_size
  maximum_batching_window_in_seconds = var.batching_window_seconds
  enabled                            = true
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

# EventBridge Target to SQS
resource "aws_cloudwatch_event_target" "send_to_sqs" {
  rule      = aws_cloudwatch_event_rule.ecs_update_service.name
  target_id = "SendToSQS"
  arn       = aws_sqs_queue.alerts.arn
}
