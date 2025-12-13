output "sqs_queue_arn" {
  description = "ARN of the SQS queue for alerts"
  value       = aws_sqs_queue.alerts.arn
}

output "sqs_queue_url" {
  description = "URL of the SQS queue for alerts"
  value       = aws_sqs_queue.alerts.url
}

output "lambda_function_arn" {
  description = "ARN of the Slack notifier Lambda function"
  value       = aws_lambda_function.slack_notifier.arn
}

output "lambda_function_name" {
  description = "Name of the Slack notifier Lambda function"
  value       = aws_lambda_function.slack_notifier.function_name
}
