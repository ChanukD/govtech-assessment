# Identity and tagging

variable "project" {
  type        = string
  description = "Short project identifier. Forms the first segment of every resource name and the Project tag."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project))
    error_message = "project must be 2-21 characters, lower-case alphanumeric or hyphen, and start with a letter."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment. Forms the second segment of every resource name and the Environment tag."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  type        = string
  description = "Team or individual accountable for this stack. Applied as the Owner tag for cost allocation."
}

variable "aws_region" {
  type        = string
  description = "AWS region hosting the stack. Everything except the CloudFront WAF web ACL is created here."
  default     = "ap-southeast-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid region identifier, for example ap-southeast-1."
  }
}

# Network

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC. Must be large enough to carve three /24 subnet tiers across the configured AZs."
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, for example 10.0.0.0/16."
  }

  validation {
    condition     = tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be /20 or larger to leave room for the three subnet tiers."
  }
}

variable "az_count" {
  type        = number
  description = "Number of availability zones to spread the subnet tiers across."
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3. Two is the minimum for an ALB; three is the practical maximum for this workload."
  }
}

# Container images

variable "api_image_tag" {
  type        = string
  description = "Image tag for the API service, resolved against the API ECR repository. Set per deployment by CI."
}

variable "worker_image_tag" {
  type        = string
  description = "Image tag for the worker service, resolved against the worker ECR repository. Set per deployment by CI."
}

variable "ecr_max_image_count" {
  type        = number
  description = "Number of tagged images to retain per ECR repository before the lifecycle policy expires the oldest."
  default     = 10

  validation {
    condition     = var.ecr_max_image_count >= 1 && var.ecr_max_image_count <= 100
    error_message = "ecr_max_image_count must be between 1 and 100."
  }
}

# ECS services

variable "api_container_port" {
  type        = number
  description = "Port the API container listens on. The ALB target group and the API security group both follow this."
  default     = 8000

  validation {
    condition     = var.api_container_port > 0 && var.api_container_port <= 65535
    error_message = "api_container_port must be a valid TCP port."
  }
}

variable "alb_listener_port" {
  type        = number
  description = "Port the load balancer listens on. HTTP, because TLS terminates at CloudFront and this environment provisions no ACM certificate."
  default     = 80

  validation {
    condition     = var.alb_listener_port > 0 && var.alb_listener_port <= 65535
    error_message = "alb_listener_port must be a valid TCP port."
  }
}

variable "api_task_cpu" {
  type        = number
  description = "Fargate CPU units for one API task. Must pair with api_task_memory per the Fargate size table."
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.api_task_cpu)
    error_message = "api_task_cpu must be one of the supported Fargate values: 256, 512, 1024, 2048, 4096."
  }
}

variable "api_task_memory" {
  type        = number
  description = "Fargate memory (MiB) for one API task."
  default     = 1024
}

variable "api_desired_count" {
  type        = number
  description = "Number of API tasks to run. Fixed: this environment has no autoscaling policy."
  default     = 2

  validation {
    condition     = var.api_desired_count >= 1
    error_message = "api_desired_count must be at least 1."
  }
}

variable "worker_task_cpu" {
  type        = number
  description = "Fargate CPU units for one worker task."
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.worker_task_cpu)
    error_message = "worker_task_cpu must be one of the supported Fargate values: 256, 512, 1024, 2048, 4096."
  }
}

variable "worker_task_memory" {
  type        = number
  description = "Fargate memory (MiB) for one worker task."
  default     = 1024
}

variable "worker_desired_count" {
  type        = number
  description = "Number of worker tasks consuming the queue. Fixed: this environment has no queue-depth scaling."
  default     = 1

  validation {
    condition     = var.worker_desired_count >= 1
    error_message = "worker_desired_count must be at least 1."
  }
}

# Queue

variable "queue_visibility_timeout_seconds" {
  type        = number
  description = "How long a claimed message stays invisible. Must exceed the worst-case transformation time."
  default     = 30

  validation {
    condition     = var.queue_visibility_timeout_seconds >= 0 && var.queue_visibility_timeout_seconds <= 43200
    error_message = "queue_visibility_timeout_seconds must be between 0 and 43200 (12 hours)."
  }
}

variable "queue_max_receive_count" {
  type        = number
  description = "Receives of a single message before it is redriven to the dead-letter queue."
  default     = 3

  validation {
    condition     = var.queue_max_receive_count >= 1 && var.queue_max_receive_count <= 1000
    error_message = "queue_max_receive_count must be between 1 and 1000."
  }
}

# Database

variable "db_instance_class" {
  type        = string
  description = "RDS instance class. Graviton burstable classes are the intended shape for this workload."
  default     = "db.t4g.micro"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.db_instance_class))
    error_message = "db_instance_class must be a valid RDS instance class, for example db.t4g.micro."
  }

  validation {
    condition     = can(regex("^db\\.(t3|t4g|m6g|m7g|r6g)\\.", var.db_instance_class))
    error_message = "db_instance_class must be a burstable or Graviton general-purpose class. Larger families need a documented capacity review."
  }
}

variable "db_engine_version" {
  type        = string
  description = "PostgreSQL major version. Minor versions are applied automatically in the maintenance window."
  default     = "16"
}

variable "db_allocated_storage" {
  type        = number
  description = "Initial storage (GiB) for the database instance."
  default     = 20

  validation {
    condition     = var.db_allocated_storage >= 20
    error_message = "db_allocated_storage must be at least 20 GiB, the gp3 minimum for PostgreSQL."
  }
}

variable "db_max_allocated_storage" {
  type        = number
  description = "Upper bound (GiB) for storage autoscaling."
  default     = 100
}

variable "db_backup_retention_days" {
  type        = number
  description = "Days of automated backups to retain."
  default     = 7

  validation {
    condition     = var.db_backup_retention_days >= 1 && var.db_backup_retention_days <= 35
    error_message = "db_backup_retention_days must be between 1 and 35. Zero would disable point-in-time recovery."
  }
}

variable "db_deletion_protection" {
  type        = bool
  description = "Whether the database refuses deletion. Disabled in dev so the environment can be torn down."
  default     = false
}

# Edge

variable "cloudfront_price_class" {
  type        = string
  description = "CloudFront edge locations to use. The cheapest class covers the intended user base."
  default     = "PriceClass_200"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "cloudfront_price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "waf_trigger_rate_limit" {
  type        = number
  description = "Requests per five-minute window from a single IP to the run-trigger endpoint before WAF blocks it."
  default     = 100

  validation {
    condition     = var.waf_trigger_rate_limit >= 10
    error_message = "waf_trigger_rate_limit must be at least 10, the AWS minimum for a rate-based statement."
  }
}

# Observability

variable "log_retention_days" {
  type        = number
  description = "CloudWatch Logs retention for every log group in the stack."
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
