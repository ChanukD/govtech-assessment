variable "name_prefix" {
  type        = string
  description = "Prefix applied to every resource name in this module."
}

variable "queue_name" {
  type        = string
  description = "Logical queue name, combined with name_prefix. The dead-letter queue takes the same name with a -dlq suffix."

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,40}$", var.queue_name))
    error_message = "queue_name must be alphanumeric, hyphen or underscore, up to 40 characters."
  }
}

variable "visibility_timeout_seconds" {
  type        = number
  description = "How long a received message is hidden from other consumers. Must exceed the worst-case processing time or a slow run will be redelivered while it is still being worked."
  default     = 30

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be between 0 and 43200."
  }
}

variable "message_retention_seconds" {
  type        = number
  description = "How long an unconsumed message survives on the main queue."
  default     = 345600 # 4 days

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be between 60 and 1209600 (14 days)."
  }
}

variable "dlq_message_retention_seconds" {
  type        = number
  description = "How long a failed message survives on the dead-letter queue. Longer than the main queue, because a DLQ message is evidence and needs time to be investigated."
  default     = 1209600 # 14 days, the maximum

  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600
    error_message = "dlq_message_retention_seconds must be between 60 and 1209600 (14 days)."
  }
}

variable "receive_wait_time_seconds" {
  type        = number
  description = "Long-poll duration. 20 is the maximum and the right value for a worker: it removes empty-receive churn."
  default     = 20

  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "receive_wait_time_seconds must be between 0 and 20."
  }
}

variable "max_receive_count" {
  type        = number
  description = "Receives of one message before it is moved to the dead-letter queue."
  default     = 3

  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "max_receive_count must be between 1 and 1000."
  }
}
