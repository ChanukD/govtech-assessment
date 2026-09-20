output "queue_url" {
  description = "URL of the main run queue, passed to the API and worker as configuration."
  value       = aws_sqs_queue.main.url
}

output "queue_arn" {
  description = "ARN of the main run queue, used to scope the API and worker IAM policies."
  value       = aws_sqs_queue.main.arn
}

output "queue_name" {
  description = "Name of the main run queue, the form CloudWatch metric dimensions require."
  value       = aws_sqs_queue.main.name
}

output "dlq_url" {
  description = "URL of the dead-letter queue."
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue."
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  description = "Name of the dead-letter queue, for the depth alarm."
  value       = aws_sqs_queue.dlq.name
}
