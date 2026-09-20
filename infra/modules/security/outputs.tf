output "alb_security_group_id" {
  description = "Security group for the load balancer."
  value       = aws_security_group.alb.id
}

output "api_security_group_id" {
  description = "Security group for the API tasks."
  value       = aws_security_group.api.id
}

output "worker_security_group_id" {
  description = "Security group for the worker tasks."
  value       = aws_security_group.worker.id
}

output "database_security_group_id" {
  description = "Security group for the database instance."
  value       = aws_security_group.database.id
}

output "api_task_role_arn" {
  description = "Task role the API container assumes. Send to the queue, read the database secret, nothing else."
  value       = aws_iam_role.api_task.arn
}

output "api_execution_role_arn" {
  description = "Execution role the ECS agent uses to start API tasks: pull the image, write logs, inject the secret."
  value       = aws_iam_role.api_execution.arn
}

output "worker_task_role_arn" {
  description = "Task role the worker container assumes. Consume the queue, read the source bucket, read the database secret."
  value       = aws_iam_role.worker_task.arn
}

output "worker_execution_role_arn" {
  description = "Execution role the ECS agent uses to start worker tasks."
  value       = aws_iam_role.worker_execution.arn
}
