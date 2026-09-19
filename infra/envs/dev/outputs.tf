# Outputs are limited to what an operator or a CI pipeline actually needs: where the
# application lives, where to push images, and the identifiers needed to inspect the
# stack. No credential is exposed here — the database password exists only inside
# Secrets Manager and is never read back into state as an output.

output "application_url" {
  description = "Public entry point for the SPA and, under /api/*, the API."
  value       = "https://${module.s3_site.distribution_domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID, for cache invalidation after a frontend deploy."
  value       = module.s3_site.distribution_id
}

output "site_bucket_name" {
  description = "S3 bucket the React build is synced to."
  value       = module.s3_site.bucket_name
}

output "source_bucket_name" {
  description = "S3 bucket the worker reads input files from."
  value       = module.s3_source.bucket_name
}

output "ecr_repository_urls" {
  description = "Image repository URLs, keyed by service name, for CI to build and push to."
  value       = module.ecr.repository_urls
}

output "ecs_cluster_name" {
  description = "ECS cluster running the API and worker services."
  value       = aws_ecs_cluster.main.name
}

output "queue_url" {
  description = "URL of the run queue, for operational inspection."
  value       = module.sqs.queue_url
}

output "dlq_url" {
  description = "URL of the dead-letter queue. Messages here are runs that failed every retry."
  value       = module.sqs.dlq_url
}

output "alarm_topic_arn" {
  description = "SNS topic every CloudWatch alarm publishes to. Subscriptions are added per environment."
  value       = module.observability.sns_topic_arn
}

# Marked sensitive: the database is not publicly reachable and its hostname is not a
# credential, but it is internal topology that has no reason to appear in CI logs.
output "db_endpoint" {
  description = "Database endpoint, host:port. Reachable only from the worker and API security groups."
  value       = module.rds.endpoint
  sensitive   = true
}

# Marked sensitive: the ARN itself is not secret, but it addresses the credential, and
# keeping it out of plan output avoids pointing at it unnecessarily. The secret value
# is never output in any form.
output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the database credentials."
  value       = module.rds.secret_arn
  sensitive   = true
}

output "vpc_id" {
  description = "VPC containing the stack."
  value       = module.network.vpc_id
}
