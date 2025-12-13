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

variable "batch_size" {
  description = "Maximum number of messages to batch before sending to Slack"
  type        = number
  default     = 10
}

variable "batching_window_seconds" {
  description = "Maximum time to wait for batching (max 300)"
  type        = number
  default     = 300

  validation {
    condition     = var.batching_window_seconds >= 0 && var.batching_window_seconds <= 300
    error_message = "batching_window_seconds must be between 0 and 300."
  }
}
