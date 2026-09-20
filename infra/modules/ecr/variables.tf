variable "name_prefix" {
  type        = string
  description = "Prefix applied to every repository name."
}

variable "repository_names" {
  type        = set(string)
  description = "Logical repository names to create, one per service. A set, so repositories are keyed by name in state rather than by list position."

  validation {
    condition     = length(var.repository_names) > 0
    error_message = "at least one repository name is required."
  }

  validation {
    condition     = alltrue([for n in var.repository_names : can(regex("^[a-z][a-z0-9-]{0,40}$", n))])
    error_message = "repository names must be lower-case alphanumeric or hyphen and start with a letter."
  }
}

variable "image_tag_mutability" {
  type        = string
  description = "Whether tags can be overwritten. IMMUTABLE means a deployed tag always refers to the same image."
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  type        = bool
  description = "Whether to scan images for vulnerabilities on push."
  default     = true
}

variable "force_delete" {
  type        = bool
  description = "Whether `terraform destroy` may delete a repository that still contains images. True only for disposable environments."
  default     = false
}

variable "encryption_type" {
  type        = string
  description = "Encryption for images at rest. AES256 uses the ECR-managed key; KMS adds cost and key management for no benefit here."
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be AES256 or KMS."
  }
}

variable "max_image_count" {
  type        = number
  description = "Tagged images to retain per repository before the oldest are expired."
  default     = 10

  validation {
    condition     = var.max_image_count >= 1 && var.max_image_count <= 100
    error_message = "max_image_count must be between 1 and 100."
  }
}

variable "untagged_expiry_days" {
  type        = number
  description = "Days before an untagged image is expired. Untagged images are build layers no deployment references."
  default     = 7

  validation {
    condition     = var.untagged_expiry_days >= 1
    error_message = "untagged_expiry_days must be at least 1."
  }
}
