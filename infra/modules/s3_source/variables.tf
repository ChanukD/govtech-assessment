variable "name_prefix" {
  type        = string
  description = "Prefix applied to the bucket name. The account ID and region are appended to keep the name globally unique."
}

variable "force_destroy" {
  type        = bool
  description = "Whether `terraform destroy` may delete a bucket that still holds objects. True only for disposable environments."
  default     = false
}

variable "noncurrent_version_expiration_days" {
  type        = number
  description = "Days a superseded object version is retained. Versioning is always on — this bounds what it costs."
  default     = 30

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1."
  }
}

variable "abort_incomplete_multipart_days" {
  type        = number
  description = "Days before an incomplete multipart upload is aborted and its parts reclaimed."
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_days >= 1
    error_message = "abort_incomplete_multipart_days must be at least 1."
  }
}
