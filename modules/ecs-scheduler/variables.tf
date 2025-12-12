variable "service_name" {
  description = "ECS Service name"
  type        = string
}

variable "cluster_name" {
  description = "ECS Cluster name"
  type        = string
}

variable "ecs_service_arn" {
  description = "ECS Service ARN"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "scale_up_cron" {
  description = "Cron expression for scale up (KST timezone)"
  type        = string
  default     = "cron(0 0 ? * MON-FRI *)" # 09:00 KST weekdays
}

variable "scale_down_cron" {
  description = "Cron expression for scale down (KST timezone)"
  type        = string
  default     = "cron(0 9 ? * MON-FRI *)" # 18:00 KST weekdays
}

variable "scale_up_count" {
  description = "Desired count when scaling up"
  type        = number
  default     = 1
}

variable "scale_down_count" {
  description = "Desired count when scaling down"
  type        = number
  default     = 0
}
