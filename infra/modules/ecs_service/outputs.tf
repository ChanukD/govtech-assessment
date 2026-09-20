output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.this.name
}

output "service_arn" {
  description = "ARN of the ECS service."
  value       = aws_ecs_service.this.id
}

output "task_definition_arn" {
  description = "ARN of the task definition revision this service currently runs."
  value       = aws_ecs_task_definition.this.arn
}

output "container_name" {
  description = "Container name inside the task definition, needed for ECS Exec and for load balancer registration."
  value       = local.container_name
}
