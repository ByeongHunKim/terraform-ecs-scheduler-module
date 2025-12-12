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

variable "cluster_name" {
  description = "ECS Cluster name"
  type        = string
  default     = "terraform-study-dev-cluster"
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}
