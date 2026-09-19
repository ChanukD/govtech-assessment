output "service_name" {
  description = "Name of the ECS service."
  value       = ""
}

output "service_arn" {
  description = "ARN of the ECS service."
  value       = ""
}

output "task_definition_arn" {
  description = "ARN of the task definition revision this service currently runs."
  value       = ""
}

output "container_name" {
  description = "Container name inside the task definition, needed for ECS Exec and for load balancer registration."
  value       = ""
}
