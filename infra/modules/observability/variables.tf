# Alarm targets are passed in as plain names and ARN suffixes rather than as module
# objects. That keeps this module free of dependencies on the modules it watches, so
# the log groups it creates can be consumed by the ECS services without a cycle.

variable "name_prefix" {
  type        = string
  description = "Prefix applied to every resource name in this module."
}

variable "service_names" {
  type        = set(string)
  description = "Logical service names to create log groups for. A set, so log groups are keyed by name in state."

  validation {
    condition     = length(var.service_names) > 0
    error_message = "at least one service name is required."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Retention applied to every log group this module creates."
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}

# ---------------------------------------------------------------------------------
# Alarm targets
# ---------------------------------------------------------------------------------

variable "ecs_cluster_name" {
  type        = string
  description = "ECS cluster name, a dimension on the service CPU and memory alarms."
}

variable "api_service_name" {
  type        = string
  description = "API ECS service name, a dimension on its utilisation alarms."
}

variable "worker_service_name" {
  type        = string
  description = "Worker ECS service name, a dimension on its utilisation alarms."
}

variable "queue_name" {
  type        = string
  description = "Main queue name, a dimension on the message-age alarm."
}

variable "dlq_name" {
  type        = string
  description = "Dead-letter queue name, a dimension on the DLQ depth alarm."
}

variable "alb_arn_suffix" {
  type        = string
  description = "Load balancer ARN suffix, a dimension on the 5xx and latency alarms."
}

variable "target_group_arn_suffix" {
  type        = string
  description = "Target group ARN suffix, a dimension on the healthy-host alarm."
}

variable "db_instance_identifier" {
  type        = string
  description = "Database instance identifier, a dimension on the database alarms."
}

# ---------------------------------------------------------------------------------
# Thresholds
# ---------------------------------------------------------------------------------

variable "dlq_depth_threshold" {
  type        = number
  description = "Messages on the dead-letter queue before alarming. Zero-tolerance: any DLQ message is a run that failed every retry."
  default     = 0
}

variable "queue_message_age_alarm" {
  type        = number
  description = "Age in seconds of the oldest queued message before alarming. Indicates the worker has stopped keeping up or stopped consuming."
  default     = 300

  validation {
    condition     = var.queue_message_age_alarm > 0
    error_message = "queue_message_age_alarm must be positive."
  }
}

variable "api_5xx_threshold" {
  type        = number
  description = "Target-generated 5xx responses in one period before alarming."
  default     = 5
}

variable "api_latency_threshold_seconds" {
  type        = number
  description = "p99 target response time in seconds before alarming. The API only inserts a row and publishes, so it should be far below this."
  default     = 2
}

variable "cpu_utilisation_threshold" {
  type        = number
  description = "Service CPU utilisation percentage before alarming."
  default     = 80

  validation {
    condition     = var.cpu_utilisation_threshold > 0 && var.cpu_utilisation_threshold <= 100
    error_message = "cpu_utilisation_threshold must be between 1 and 100."
  }
}

variable "memory_utilisation_threshold" {
  type        = number
  description = "Service memory utilisation percentage before alarming."
  default     = 80

  validation {
    condition     = var.memory_utilisation_threshold > 0 && var.memory_utilisation_threshold <= 100
    error_message = "memory_utilisation_threshold must be between 1 and 100."
  }
}

variable "db_cpu_threshold" {
  type        = number
  description = "Database CPU utilisation percentage before alarming."
  default     = 80
}

variable "db_free_storage_threshold" {
  type        = number
  description = "Free storage in bytes before alarming. Defaults to roughly 2 GiB; the caller scales it to the allocated storage."
  default     = 2147483648
}

variable "alarm_evaluation_periods" {
  type        = number
  description = "Consecutive periods a metric must breach before the alarm fires."
  default     = 2

  validation {
    condition     = var.alarm_evaluation_periods >= 1
    error_message = "alarm_evaluation_periods must be at least 1."
  }
}

variable "alarm_period_seconds" {
  type        = number
  description = "Metric period each evaluation covers."
  default     = 60

  validation {
    condition     = contains([10, 30, 60, 300, 900, 3600], var.alarm_period_seconds)
    error_message = "alarm_period_seconds must be 10, 30, 60, 300, 900 or 3600."
  }
}
