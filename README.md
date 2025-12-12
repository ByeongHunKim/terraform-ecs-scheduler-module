# Terraform ECS Scheduler Module

A modular Terraform project for managing ECS service scheduling (Scale Up/Down) and sending Slack notifications upon state changes.

## 📂 Directory Structure

```
terraform/
├── modules/
│   └── ecs-scheduler/    # Core module for ECS scheduling
│       ├── main.tf       # IAM Roles, EventBridge Schedule resources
│       ├── variables.tf  # Input variables
│       └── outputs.tf    # Output values
├── slack-notifier/       # Lambda function for Slack notifications
│   └── index.py
├── main.tf               # Root configuration (SNS, Lambda, module calls)
├── variables.tf          # Global variables
└── terraform.tfvars      # Environment variables and settings (example)
```

## 🚀 Usage

### 1. Terraform Cloud Setup

This project is configured to use Terraform Cloud as the state backend.

1.  Update the `organization` and `workspace` names in the `cloud` block at the top of `terraform/main.tf` to match your environment.

    ```hcl
    terraform {
      cloud {
        organization = "my-org"
        workspaces {
          name = "ecs-scheduler-workspace"
        }
      }
    }
    ```

2.  Log in to Terraform Cloud.

    ```bash
    terraform login
    ```

### 2. Initialize

Download Terraform plugins and modules.

```bash
cd terraform
terraform init
```

### 3. Plan

Preview the infrastructure changes.

```bash
terraform plan
```

### 4. Apply

Deploy the resources to your AWS environment.

```bash
terraform apply
```

### 5. Disable Scheduling for Specific Services

To disable or modify only the Scale Down schedule for a specific service (e.g., `api_scheduler`):

```bash
terraform apply -target=module.api_scheduler.aws_scheduler_schedule.scale_down
```

## ➕ Adding a New Service

Simply add the following block to `terraform/main.tf`:

```hcl
module "new_service_scheduler" {
  source          = "./modules/ecs-scheduler"
  
  service_name    = "new-service-dev"
  cluster_name    = aws_ecs_cluster.app-cluster-dev.name
  ecs_service_arn = aws_ecs_service.new-service-dev.id
  environment     = var.environment
  
  # Optional: If you need custom cron expressions (Default: Weekdays 09:00 / 18:00 KST)
  # scale_up_cron   = "cron(0 0 ? * MON-FRI *)"
  # scale_down_cron = "cron(0 9 ? * MON-FRI *)"
}
```

## 🔔 Slack Notifications

To receive Slack notifications, you must set the Webhook URL in `terraform.tfvars`.

```hcl
slack_webhook_url = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

Notifications passed on the following events:
*   ECS Scheduling Succeeded (`SUCCEEDED`)
*   ECS Scheduling Failed (`FAILED`)

## 📋 Key Features

*   **Modular Design**: Reuse scheduler settings easily with `modules/ecs-scheduler`.
*   **EventBridge Scheduler**: Uses the latest `aws_scheduler_schedule` resources for reliable scheduling.
*   **Timezone Support**: Defaults to `Asia/Seoul` timezone for intuitive cron expressions.
*   **Slack Integration**: Real-time execution results sent to Slack via Lambda and SNS.
