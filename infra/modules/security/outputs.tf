output "alb_security_group_id" {
  description = "Security group for the load balancer."
  value       = ""
}

output "api_security_group_id" {
  description = "Security group for the API tasks."
  value       = ""
}

output "worker_security_group_id" {
  description = "Security group for the worker tasks."
  value       = ""
}

output "database_security_group_id" {
  description = "Security group for the database instance."
  value       = ""
}

output "api_task_role_arn" {
  description = "Task role the API container assumes. Send to the queue, read the database secret, nothing else."
  value       = ""
}

output "api_execution_role_arn" {
  description = "Execution role the ECS agent uses to start API tasks: pull the image, write logs, inject the secret."
  value       = ""
}

output "worker_task_role_arn" {
  description = "Task role the worker container assumes. Consume the queue, read the source bucket, read the database secret."
  value       = ""
}

output "worker_execution_role_arn" {
  description = "Execution role the ECS agent uses to start worker tasks."
  value       = ""
}
