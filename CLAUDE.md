# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Terraform module for AWS ECS service scheduling (auto scale up/down) with Slack notifications. Uses EventBridge Scheduler to trigger ECS UpdateService calls at specified times, with CloudTrail events captured and sent to Slack via SNS and Lambda.

## Directory Structure

```
modules/
├── ecs-scheduler/      # Per-service scheduling (IAM + EventBridge schedules)
└── slack-notifier/     # SNS + Lambda + EventBridge Rule for notifications
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
EventBridge Scheduler → ECS UpdateService → CloudTrail → EventBridge Rule → SNS → Lambda → Slack

**Modules:**
- `modules/ecs-scheduler/` - Creates IAM role and two `aws_scheduler_schedule` resources (scale_up, scale_down) per service
- `modules/slack-notifier/` - Creates SNS topic, Lambda function, EventBridge rule for CloudTrail events

## Adding a New ECS Service

Add module block in `environments/<env>/main.tf`:

```hcl
module "service_scheduler" {
  source          = "../../modules/ecs-scheduler"
  service_name    = "service-name"
  cluster_name    = var.cluster_name
  ecs_service_arn = "arn:aws:ecs:ap-northeast-2:ACCOUNT_ID:service/${var.cluster_name}/service-name"
  environment     = var.environment
}
```

## Configuration Notes

- **Timezone**: Cron expressions use `Asia/Seoul` (KST)
- **Backend**: Terraform Cloud with per-environment workspaces
- **AWS Region**: `ap-northeast-2` (Seoul)
- **Terraform**: >= 1.6.0, AWS provider ~> 5.95.0
- **Sensitive vars**: `slack_webhook_url` should be set in Terraform Cloud
