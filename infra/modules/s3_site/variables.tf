variable "name_prefix" {
  type        = string
  description = "Prefix applied to every resource name in this module."
}

variable "alb_dns_name" {
  type        = string
  description = "DNS name of the load balancer, used as the second CloudFront origin."
}

variable "api_path_pattern" {
  type        = string
  description = "Path pattern routed to the ALB origin instead of the S3 origin. Everything else is served from the bucket."
  default     = "/api/*"
}

variable "default_root_object" {
  type        = string
  description = "Object returned for a request to the distribution root."
  default     = "index.html"
}

variable "price_class" {
  type        = string
  description = "Edge locations the distribution uses."
  default     = "PriceClass_200"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "spa_error_response_path" {
  type        = string
  description = "Object returned for 403 and 404 from the S3 origin, so client-side routes resolve to the SPA rather than an S3 error."
  default     = "/index.html"
}

# ---------------------------------------------------------------------------------
# WAF
# ---------------------------------------------------------------------------------

variable "waf_managed_rule_groups" {
  type        = list(string)
  description = "AWS-managed rule groups to attach, in evaluation order. Names are resolved against the AWS vendor."
  default = [
    "AWSManagedRulesCommonRuleSet",
    "AWSManagedRulesKnownBadInputsRuleSet",
    "AWSManagedRulesAmazonIpReputationList",
  ]

  validation {
    condition     = length(var.waf_managed_rule_groups) > 0
    error_message = "at least one managed rule group is required."
  }
}

variable "waf_rate_limit" {
  type        = number
  description = "Requests per five-minute window from one IP to the rate-limited path before WAF blocks that IP."
  default     = 100

  validation {
    condition     = var.waf_rate_limit >= 10
    error_message = "waf_rate_limit must be at least 10, the AWS minimum for a rate-based statement."
  }
}

variable "waf_rate_limited_path" {
  type        = string
  description = "Path the rate-based rule is scoped to. Scoped rather than global so that polling for run status is not rate-limited alongside triggering runs."
  default     = "/api/v1/runs"

  validation {
    condition     = startswith(var.waf_rate_limited_path, "/")
    error_message = "waf_rate_limited_path must start with /."
  }
}
