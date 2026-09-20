output "queue_url" {
  description = "URL of the main run queue, passed to the API and worker as configuration."
  value       = ""
}

output "queue_arn" {
  description = "ARN of the main run queue, used to scope the API and worker IAM policies."
  value       = ""
}

output "queue_name" {
  description = "Name of the main run queue, the form CloudWatch metric dimensions require."
  value       = ""
}

output "dlq_url" {
  description = "URL of the dead-letter queue."
  value       = ""
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue."
  value       = ""
}

output "dlq_name" {
  description = "Name of the dead-letter queue, for the depth alarm."
  value       = ""
}
