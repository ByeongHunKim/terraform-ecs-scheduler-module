variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "slack_webhook_url" {
  description = "Slack Webhook URL for notifications"
  type        = string
  sensitive   = true
}
