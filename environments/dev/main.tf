# Slack Notification Infrastructure
module "slack_notifier" {
  source            = "../../modules/slack-notifier"
  environment       = var.environment
  slack_webhook_url = var.slack_webhook_url
  # Optional
  # batch_size              = 2   # 2 messages threshold, DEFAULT 10
  # batching_window_seconds = 300  # MAX 5M , DEFAULT 300
}

# ECS Scheduler - example service
module "example_scheduler" {
  source       = "../../modules/ecs-scheduler"
  service_name = "example"
  cluster_name = var.cluster_name
  environment  = var.environment

  scale_up_cron   = "cron(0 0 ? * MON-FRI *)"
  scale_down_cron = "cron(0 9 ? * MON-FRI *)"
}

# Add more ECS service schedulers here as needed
# module "another_service_scheduler" {
#   source       = "../../modules/ecs-scheduler"
#   service_name = "another-service"
#   cluster_name = var.cluster_name
#   environment  = var.environment
#   scale_up_cron   = "cron(0 0 ? * MON-FRI *)"
#   scale_down_cron = "cron(0 9 ? * MON-FRI *)"
# }
