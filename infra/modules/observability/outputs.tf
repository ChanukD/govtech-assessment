output "log_group_names" {
  description = "Log group names keyed by service name, passed to the ECS task definitions."
  value       = { for k, g in aws_cloudwatch_log_group.service : k => g.name }
}

output "log_group_arns" {
  description = "Log group ARNs keyed by service name, used to scope the execution roles' write permissions."
  value       = { for k, g in aws_cloudwatch_log_group.service : k => g.arn }
}

output "sns_topic_arn" {
  description = "SNS topic every alarm in this module publishes to."
  value       = aws_sns_topic.alarms.arn
}

output "alarm_names" {
  description = "Names of every alarm created, for reference in runbooks."
  value = concat(
    [
      aws_cloudwatch_metric_alarm.dlq_not_empty.alarm_name,
      aws_cloudwatch_metric_alarm.queue_backlog.alarm_name,
      aws_cloudwatch_metric_alarm.api_5xx.alarm_name,
      aws_cloudwatch_metric_alarm.api_latency.alarm_name,
      aws_cloudwatch_metric_alarm.api_unhealthy_hosts.alarm_name,
      aws_cloudwatch_metric_alarm.db_cpu.alarm_name,
      aws_cloudwatch_metric_alarm.db_free_storage.alarm_name,
    ],
    [for a in aws_cloudwatch_metric_alarm.service_cpu : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.service_memory : a.alarm_name],
  )
}
