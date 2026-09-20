output "log_group_names" {
  description = "Log group names keyed by service name, passed to the ECS task definitions."
  value       = { for n in var.service_names : n => "" }
}

output "log_group_arns" {
  description = "Log group ARNs keyed by service name, used to scope the execution roles' write permissions."
  value       = { for n in var.service_names : n => "" }
}

output "sns_topic_arn" {
  description = "SNS topic every alarm in this module publishes to."
  value       = ""
}

output "alarm_names" {
  description = "Names of every alarm created, for reference in runbooks."
  value       = []
}
