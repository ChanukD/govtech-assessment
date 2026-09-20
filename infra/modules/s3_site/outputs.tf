output "bucket_name" {
  description = "Name of the static site bucket. The React build is synced here."
  value       = ""
}

output "bucket_arn" {
  description = "ARN of the static site bucket."
  value       = ""
}

output "distribution_id" {
  description = "CloudFront distribution ID, needed to invalidate the cache after a deploy."
  value       = ""
}

output "distribution_domain_name" {
  description = "Domain name of the distribution. This is the application's public entry point."
  value       = ""
}

output "distribution_hosted_zone_id" {
  description = "CloudFront's hosted zone ID, for an alias record if a custom domain is added later."
  value       = ""
}

output "web_acl_arn" {
  description = "ARN of the CloudFront-scoped web ACL."
  value       = ""
}
