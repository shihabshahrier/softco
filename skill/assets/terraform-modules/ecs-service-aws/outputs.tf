output "service_arn" {
  description = "ECS service ARN"
  value       = aws_ecs_service.this.id
}

output "task_role_arn" {
  description = "IAM role assumed by the running container (use for app permissions)"
  value       = aws_iam_role.task.arn
}

output "task_definition_arn" {
  description = "Active task definition ARN"
  value       = aws_ecs_task_definition.this.arn
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.this.name
}
