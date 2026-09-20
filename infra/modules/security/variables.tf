variable "name_prefix" {
  type        = string
  description = "Prefix applied to every resource name in this module."
}

variable "vpc_id" {
  type        = string
  description = "VPC the security groups are created in."
}

variable "vpc_endpoints_security_group_id" {
  type        = string
  description = "Security group of the interface VPC endpoints, created by the network module. This module owns its ingress rules so they can reference the task security groups by ID."
}

variable "api_container_port" {
  type        = number
  description = "Port the API listens on. The ALB is allowed to reach the API tasks on this port and no other."

  validation {
    condition     = var.api_container_port > 0 && var.api_container_port <= 65535
    error_message = "api_container_port must be a valid TCP port."
  }
}

variable "alb_listener_port" {
  type        = number
  description = "Port the load balancer listens on. Must match the alb module's listener_port."
  default     = 80

  validation {
    condition     = var.alb_listener_port > 0 && var.alb_listener_port <= 65535
    error_message = "alb_listener_port must be a valid TCP port."
  }
}

variable "db_port" {
  type        = number
  description = "Port the database listens on."
  default     = 5432
}

variable "s3_gateway_prefix_list_id" {
  type        = string
  description = "Prefix list of the S3 gateway endpoint, from the network module. The worker's S3 egress rule targets this rather than a CIDR."
}

variable "alb_source_prefix_list_name" {
  type        = string
  description = "AWS-managed prefix list allowed to reach the ALB. Defaults to CloudFront's origin-facing ranges, so the ALB is not open to the whole internet."
  default     = "com.amazonaws.global.cloudfront.origin-facing"
}

# Resources the task roles are scoped to. Passed in as ARNs so that every IAM policy
# in the stack names specific resources rather than wildcards.

variable "source_bucket_arn" {
  type        = string
  description = "ARN of the source-data bucket. Only the worker role is granted read access to it."
}

variable "main_queue_arn" {
  type        = string
  description = "ARN of the run queue. The API may send to it; the worker may receive from it."
}

variable "db_secret_arn_pattern" {
  type        = string
  description = "ARN pattern of the database credentials secret, including the trailing wildcard that matches the suffix Secrets Manager appends."
}

variable "ecr_repository_arns" {
  type        = list(string)
  description = "ARNs of the repositories the execution roles may pull images from."
}

variable "log_group_arns" {
  type        = list(string)
  description = "ARNs of the log groups the execution roles may write container logs to."
}
