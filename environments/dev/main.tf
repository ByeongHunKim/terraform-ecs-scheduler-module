# Slack Notification Infrastructure
module "slack_notifier" {
  source            = "../../modules/slack-notifier"
  environment       = var.environment
  slack_webhook_url = var.slack_webhook_url
  # Optional
  # batch_size              = 2   # 2 messages threshold, DEFAULT 10
  # batching_window_seconds = 300  # MAX 5M , DEFAULT 300
}

# ECS Scheduler - nestjs service
module "nestjs_scheduler" {
  source          = "../../modules/ecs-scheduler"
  service_name    = "nestjs"
  cluster_name    = var.cluster_name
  ecs_service_arn = "arn:aws:ecs:ap-northeast-2:${var.aws_account_id}:service/${var.cluster_name}/nestjs"
  environment     = var.environment

  scale_up_cron   = "cron(00 11 * * ? *)"
  scale_down_cron = "cron(05 11 * * ? *)"
}

# Add more ECS service schedulers here as needed
# module "another_service_scheduler" {
#   source          = "../../modules/ecs-scheduler"
#   service_name    = "another-service"
#   cluster_name    = var.cluster_name
#   ecs_service_arn = "arn:aws:ecs:ap-northeast-2:${var.aws_account_id}:service/${var.cluster_name}/another-service"
#   environment     = var.environment
# }
