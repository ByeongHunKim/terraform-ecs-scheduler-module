output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "lambda_function_arn" {
  description = "ARN of the Slack notifier Lambda function"
  value       = aws_lambda_function.slack_notifier.arn
}

output "lambda_function_name" {
  description = "Name of the Slack notifier Lambda function"
  value       = aws_lambda_function.slack_notifier.function_name
}
