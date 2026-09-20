output "bucket_name" {
  description = "Name of the static site bucket. The React build is synced here."
  value       = aws_s3_bucket.site.id
}

output "bucket_arn" {
  description = "ARN of the static site bucket."
  value       = aws_s3_bucket.site.arn
}

output "distribution_id" {
  description = "CloudFront distribution ID, needed to invalidate the cache after a deploy."
  value       = aws_cloudfront_distribution.main.id
}

output "distribution_domain_name" {
  description = "Domain name of the distribution. This is the application's public entry point."
  value       = aws_cloudfront_distribution.main.domain_name
}

output "distribution_hosted_zone_id" {
  description = "CloudFront's hosted zone ID, for an alias record if a custom domain is added later."
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "web_acl_arn" {
  description = "ARN of the CloudFront-scoped web ACL."
  value       = aws_wafv2_web_acl.main.arn
}
