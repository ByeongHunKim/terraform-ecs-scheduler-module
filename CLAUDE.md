# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Terraform module for AWS ECS service scheduling (auto scale up/down) with batched Slack notifications. Uses EventBridge Scheduler with flexible time windows to trigger ECS UpdateService calls, with CloudTrail events batched via SQS and sent to Slack as summary notifications.

## Directory Structure

```
modules/
├── ecs-scheduler/      # Per-service scheduling (IAM + EventBridge schedules)
└── slack-notifier/     # SQS + Lambda + EventBridge Rule for batched notifications
environments/
├── dev/                # workspace: ecs-scheduler-dev
└── stg/                # workspace: ecs-scheduler-stg
```

## Common Commands

```bash
# Work in specific environment
cd environments/dev

# Initialize (requires Terraform Cloud login)
terraform login
terraform init

# Plan and apply
terraform plan
terraform apply

# Target specific schedule
terraform apply -target=module.nestjs_scheduler.aws_scheduler_schedule.scale_down
```

## Architecture

**Event Flow:**
```
EventBridge Scheduler (5min flexible window)
    → ECS UpdateService
    → CloudTrail
    → EventBridge Rule
    → SQS (batching: 10 msgs or 5 min)
    → Lambda
    → Slack (summary notification)
```

**Modules:**
- `modules/ecs-scheduler/` - Creates IAM role and two `aws_scheduler_schedule` resources (scale_up, scale_down) per service with flexible time window
- `modules/slack-notifier/` - Creates SQS queue, Lambda function with batch processing, EventBridge rule for CloudTrail events

## Adding a New ECS Service

Add module block in `environments/<env>/main.tf`:

```hcl
module "service_scheduler" {
  source       = "../../modules/ecs-scheduler"
  service_name = "service-name"
  cluster_name = var.cluster_name
  environment  = var.environment

  # Optional
  # flexible_time_window_minutes = 5  # 0 to disable
}
```

> `ecs_service_arn` is auto-generated from `service_name` and `cluster_name`.

## Key Variables

### ecs-scheduler
- `flexible_time_window_minutes`: Distributes execution over N minutes (default: 5, 0=OFF)
- `scale_up_cron` / `scale_down_cron`: Cron expressions in KST

### slack-notifier
- `batch_size`: Max messages before Lambda triggers (default: 10)
- `batching_window_seconds`: Max wait time for batching (default: 300, **max: 300** - AWS limit)

## Configuration Notes

- **Timezone**: Cron expressions use `Asia/Seoul` (KST)
- **Backend**: Terraform Cloud with per-environment workspaces
- **AWS Region**: `ap-northeast-2` (Seoul)
- **Terraform**: >= 1.6.0, AWS provider ~> 5.95.0
- **Sensitive vars**: `slack_webhook_url`, `aws_account_id` should be set in Terraform Cloud
- **Batching**: SQS batches messages (10 msgs or 5 min max) before Lambda sends summary to Slack

## Known Issues

### Notifications arrive separately per service
When `flexible_time_window_minutes > 0`, services execute at different times causing separate notifications.
**Fix**: Set `flexible_time_window_minutes = 0` for all services to execute simultaneously.

### batching_window_seconds max 300
AWS Lambda Event Source Mapping limits `maximum_batching_window_in_seconds` to 300. Validation added to prevent errors.
