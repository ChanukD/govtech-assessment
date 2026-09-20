locals {
  # Both ECS services get the same pair of utilisation alarms, so they are driven from
  # one map rather than written out twice.
  ecs_services = {
    api    = var.api_service_name
    worker = var.worker_service_name
  }
}

resource "aws_cloudwatch_log_group" "service" {
  for_each = var.service_names

  name              = "/ecs/${var.name_prefix}/${each.key}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.name_prefix}-${each.key}"
  }
}

# No subscriptions are created here: who gets paged differs per environment. See
# infra/README.md.
resource "aws_sns_topic" "alarms" {
  name              = "${var.name_prefix}-alarms"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name = "${var.name_prefix}-alarms"
  }
}

# Any message here is a run that failed every retry, so the threshold is zero.
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name        = "${var.name_prefix}-dlq-not-empty"
  alarm_description = "Runs have exhausted every retry and landed in the dead-letter queue."

  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  statistic   = "Maximum"

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.dlq_depth_threshold
  evaluation_periods  = 1
  period              = var.alarm_period_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.dlq_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# Catches the worker having stopped consuming, which queue depth alone would not:
# depth stays low if nothing is being enqueued either.
resource "aws_cloudwatch_metric_alarm" "queue_backlog" {
  alarm_name        = "${var.name_prefix}-queue-backlog"
  alarm_description = "Oldest queued run is ageing: the worker is behind or has stopped consuming."

  namespace   = "AWS/SQS"
  metric_name = "ApproximateAgeOfOldestMessage"
  statistic   = "Maximum"

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.queue_message_age_alarm
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.queue_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name        = "${var.name_prefix}-api-5xx"
  alarm_description = "The API is returning server errors."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_5XX_Count"
  statistic   = "Sum"

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.api_5xx_threshold
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# The API only inserts a row and publishes a message, so p99 latency rising means
# something downstream of the request path is wrong.
resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name        = "${var.name_prefix}-api-latency"
  alarm_description = "API p99 response time is above the expected envelope."

  namespace          = "AWS/ApplicationELB"
  metric_name        = "TargetResponseTime"
  extended_statistic = "p99"

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.api_latency_threshold_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_unhealthy_hosts" {
  alarm_name        = "${var.name_prefix}-api-unhealthy-hosts"
  alarm_description = "API tasks are failing their target group health check."

  namespace   = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"
  statistic   = "Maximum"

  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "service_cpu" {
  for_each = local.ecs_services

  alarm_name        = "${var.name_prefix}-${each.key}-cpu"
  alarm_description = "Sustained CPU utilisation on the ${each.key} service."

  namespace   = "AWS/ECS"
  metric_name = "CPUUtilization"
  statistic   = "Average"

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cpu_utilisation_threshold
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = each.value
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "service_memory" {
  for_each = local.ecs_services

  alarm_name        = "${var.name_prefix}-${each.key}-memory"
  alarm_description = "Sustained memory utilisation on the ${each.key} service."

  namespace   = "AWS/ECS"
  metric_name = "MemoryUtilization"
  statistic   = "Average"

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.memory_utilisation_threshold
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = each.value
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name        = "${var.name_prefix}-db-cpu"
  alarm_description = "Sustained CPU utilisation on the database."

  namespace   = "AWS/RDS"
  metric_name = "CPUUtilization"
  statistic   = "Average"

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.db_cpu_threshold
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "db_free_storage" {
  alarm_name        = "${var.name_prefix}-db-free-storage"
  alarm_description = "Database free storage is running low."

  namespace   = "AWS/RDS"
  metric_name = "FreeStorageSpace"
  statistic   = "Average"

  comparison_operator = "LessThanThreshold"
  threshold           = var.db_free_storage_threshold
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}
