## 📝 Implementation Plan: Filter ECS Scheduler Notifications

The goal of this plan is to reduce alert fatigue by filtering ECS `UpdateService` notifications in Slack so that **only** updates triggered by the EventBridge Scheduler are sent.

-----

### ⚠️ User Review Required

> [\!IMPORTANT]
> This change relies critically on the naming convention of the IAM Role created by the `ecs-scheduler` module. The IAM Role name **MUST** end with the suffix:
>
> `**-scheduler-role-${var.environment}**`
>
> If this naming convention is changed in the future, the CloudWatch Event Rule filter will need to be updated.

-----

### ⚙️ Proposed Changes

The change involves modifying the CloudWatch Event Rule in the `slack-notifier` module to include a filter that checks the identity of the user/role that triggered the ECS `UpdateService` API call.

#### Module: `modules/slack-notifier`

#### **[MODIFY] `main.tf`**

Update the `aws_cloudwatch_event_rule.ecs_update_service` resource's `event_pattern` to include a `userIdentity` filter that specifically matches the scheduler's IAM Role name using the `suffix` operator.

```hcl
  event_pattern = jsonencode({
    source      = ["aws.ecs"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["UpdateService"]
      # The new filter logic
      userIdentity = {
        sessionContext = {
          sessionIssuer = {
            # Only match callers whose userName (the IAM Role name) ends with the scheduler's specific suffix
            userName = [{ "suffix": "-scheduler-role-${var.environment}" }]
          }
        }
      }
    }
  })
```

-----

### ✅ Verification Plan

Verification relies on manual observation of Slack notifications after applying the changes and triggering different types of service updates.

#### **Manual Verification**

1.  **Apply Terraform:** Apply the changes to the **`dev`** environment.
2.  **Trigger Scheduler Update (Expected: Notification RECEIVED):**
      * Wait for a naturally scheduled scale-up/down event.
      * *OR* Manually trigger the EventBridge schedule via the AWS Console/CLI.
      * **Check:** Verify that a Slack notification is **RECEIVED**.
3.  **Manual Console Update (Expected: Notification BLOCKED):**
      * Go to the AWS Console -\> ECS -\> Service -\> Update Service -\> Force new deployment or manually change the task count.
      * **Check:** Verify that **NO** Slack notification is received.
4.  **Terraform Update (Expected: Notification BLOCKED):**
      * Run `terraform apply` to change a different property of the ECS service (e.g., CPU/Memory, or a non-scaling related tag).
      * **Check:** Verify that **NO** Slack notification is received.