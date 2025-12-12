# Slack Notification Infrastructure
module "slack_notifier" {
  source            = "../../modules/slack-notifier"
  environment       = var.environment
  slack_webhook_url = var.slack_webhook_url
}

# ECS Scheduler - nestjs service
module "nestjs_scheduler" {
  source          = "../../modules/ecs-scheduler"
  service_name    = "nestjs"
  cluster_name    = var.cluster_name
  ecs_service_arn = "arn:aws:ecs:ap-northeast-2:${var.aws_account_id}:service/${var.cluster_name}/nestjs"
  environment     = var.environment

  scale_up_cron   = "cron(0 0 ? * MON-FRI *)"
  scale_down_cron = "cron(0 9 ? * MON-FRI *)"
}

# Add more ECS service schedulers here as needed
