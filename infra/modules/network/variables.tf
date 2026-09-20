variable "name_prefix" {
  type        = string
  description = "Prefix applied to every resource name in this module."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC. Subnet ranges are derived from it with cidrsubnet(), never written down."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be /20 or larger to fit three subnet tiers across the configured AZs."
  }
}

variable "az_count" {
  type        = number
  description = "Number of availability zones to spread each subnet tier across."
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "subnet_newbits" {
  type        = number
  description = "Bits added to the VPC prefix when carving subnets. 8 against a /16 yields /24 subnets."
  default     = 8

  validation {
    condition     = var.subnet_newbits >= 4 && var.subnet_newbits <= 12
    error_message = "subnet_newbits must be between 4 and 12."
  }
}

variable "interface_endpoint_services" {
  type        = set(string)
  description = "Service names to create interface VPC endpoints for, without the com.amazonaws.<region> prefix. These replace a NAT gateway for the private subnets."
  default     = ["sqs", "ecr.api", "ecr.dkr", "logs", "secretsmanager"]
}
