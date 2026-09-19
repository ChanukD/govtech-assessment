variable "name_prefix" {
  type        = string
  description = "Prefix applied to every resource name in this module."
}

variable "vpc_id" {
  type        = string
  description = "VPC the target group is created in."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Public subnets the load balancer is placed in, one per AZ."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "an ALB requires subnets in at least two availability zones."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security groups attached to the load balancer."
}

variable "target_port" {
  type        = number
  description = "Port on the targets that the listener forwards to."

  validation {
    condition     = var.target_port > 0 && var.target_port <= 65535
    error_message = "target_port must be a valid TCP port."
  }
}

variable "listener_port" {
  type        = number
  description = "Port the load balancer listens on. HTTP, because TLS terminates at CloudFront and this environment provisions no ACM certificate."
  default     = 80
}

variable "health_check_path" {
  type        = string
  description = "Path the target group polls to decide whether a task is healthy."
  default     = "/healthz"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with /."
  }
}

variable "health_check_interval_seconds" {
  type        = number
  description = "Seconds between health checks."
  default     = 15
}

variable "health_check_timeout_seconds" {
  type        = number
  description = "Seconds to wait for a health check response before counting it as a failure."
  default     = 5
}

variable "healthy_threshold" {
  type        = number
  description = "Consecutive successful checks before a target is considered healthy."
  default     = 2
}

variable "unhealthy_threshold" {
  type        = number
  description = "Consecutive failed checks before a target is taken out of service."
  default     = 3
}

variable "deregistration_delay_seconds" {
  type        = number
  description = "How long the load balancer waits for in-flight requests to finish before deregistering a target."
  default     = 30
}

variable "idle_timeout_seconds" {
  type        = number
  description = "How long an idle connection is held open. The API returns 202 immediately, so it does not need a long timeout."
  default     = 60
}

variable "enable_deletion_protection" {
  type        = bool
  description = "Whether the load balancer refuses deletion. Off in dev so the environment stays disposable."
  default     = false
}
