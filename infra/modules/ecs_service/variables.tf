# This module is generic: it describes "a Fargate service", not "the API" or "the
# worker". The difference between the two is expressed entirely through variables.
#
# The load-balanced shape is opt-in. Leave container_port and target_group_arn unset
# and the service is created with no load balancer and no exposed port, which is what
# a queue consumer wants.

variable "name_prefix" {
  type        = string
  description = "Prefix applied to every resource name in this module."
}

variable "service_name" {
  type        = string
  description = "Logical name of this service, for example api or worker. Combined with name_prefix to name the service, task definition and container."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}$", var.service_name))
    error_message = "service_name must be lower-case alphanumeric or hyphen and start with a letter."
  }
}

variable "cluster_arn" {
  type        = string
  description = "ARN of the ECS cluster to run in."
}

variable "image_uri" {
  type        = string
  description = "Fully qualified container image URI including tag or digest."
}

variable "task_cpu" {
  type        = number
  description = "Fargate CPU units for the task."

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.task_cpu)
    error_message = "task_cpu must be a value Fargate accepts: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}

variable "task_memory" {
  type        = number
  description = "Fargate memory in MiB. Must be a combination Fargate allows for the chosen task_cpu."

  validation {
    condition     = var.task_memory >= 512 && var.task_memory % 512 == 0
    error_message = "task_memory must be at least 512 MiB and a multiple of 512."
  }
}

variable "desired_count" {
  type        = number
  description = "Number of tasks to run. Fixed — this module intentionally creates no autoscaling policy."

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count cannot be negative."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets to place tasks in."

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "at least one subnet is required."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security groups attached to the task ENIs."

  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "at least one security group is required."
  }
}

variable "task_role_arn" {
  type        = string
  description = "Role assumed by the application code inside the container."
}

variable "execution_role_arn" {
  type        = string
  description = "Role assumed by the ECS agent to pull the image, write logs and resolve secrets. Deliberately separate from task_role_arn."
}

variable "log_group_name" {
  type        = string
  description = "CloudWatch log group the container writes to. Created by the observability module."
}

variable "environment_variables" {
  type        = map(string)
  description = "Plain environment variables for the container. Never put credentials here — use secret_environment_variables."
  default     = {}
}

variable "secret_environment_variables" {
  type        = map(string)
  description = "Environment variables resolved from Secrets Manager or SSM at task start, as name => valueFrom ARN. The value never enters Terraform state."
  default     = {}
}

# ---------------------------------------------------------------------------------
# Load-balanced shape — optional
# ---------------------------------------------------------------------------------

variable "container_port" {
  type        = number
  description = "Port the container listens on. Null for services that accept no inbound traffic, such as a queue consumer."
  default     = null
}

variable "target_group_arn" {
  type        = string
  description = "Target group to register tasks with. Null creates a service with no load balancer."
  default     = null

  validation {
    condition     = var.target_group_arn == null || var.container_port != null
    error_message = "container_port must be set when target_group_arn is provided: the target group has nothing to register without a port."
  }
}

variable "health_check_grace_period_seconds" {
  type        = number
  description = "Grace period before load balancer health checks can kill a starting task. Only meaningful with a target group."
  default     = null
}

# ---------------------------------------------------------------------------------
# Behaviour
# ---------------------------------------------------------------------------------

variable "enable_execute_command" {
  type        = bool
  description = "Whether ECS Exec is permitted into running tasks. Off by default; it is a debugging path into a private subnet."
  default     = false
}

variable "stop_timeout_seconds" {
  type        = number
  description = "Grace period for the container to exit on SIGTERM. The worker uses this to finish an in-flight message rather than abandoning it."
  default     = 30

  validation {
    condition     = var.stop_timeout_seconds >= 1 && var.stop_timeout_seconds <= 120
    error_message = "stop_timeout_seconds must be between 1 and 120, the range Fargate accepts."
  }
}

variable "deployment_minimum_healthy_percent" {
  type        = number
  description = "Lower bound on running tasks during a deployment, as a percentage of desired_count."
  default     = 100
}

variable "deployment_maximum_percent" {
  type        = number
  description = "Upper bound on running tasks during a deployment, as a percentage of desired_count."
  default     = 200
}
