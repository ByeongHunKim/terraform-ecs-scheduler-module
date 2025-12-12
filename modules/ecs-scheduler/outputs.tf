output "scheduler_role_arn" {
  description = "ARN of the scheduler IAM role"
  value       = aws_iam_role.ecs_scheduler_role.arn
}

output "scale_up_schedule_arn" {
  description = "ARN of the scale up schedule"
  value       = aws_scheduler_schedule.scale_up.arn
}

output "scale_down_schedule_arn" {
  description = "ARN of the scale down schedule"
  value       = aws_scheduler_schedule.scale_down.arn
}
