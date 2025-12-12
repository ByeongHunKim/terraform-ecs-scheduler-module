variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
}

variable "slack_webhook_url" {
  description = "Slack Webhook URL for notifications"
  type        = string
  sensitive   = true
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "ecs-scheduler"
}
