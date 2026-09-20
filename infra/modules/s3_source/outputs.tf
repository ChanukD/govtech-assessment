output "bucket_name" {
  description = "Name of the source-data bucket, passed to the worker as configuration."
  value       = aws_s3_bucket.source.id
}

output "bucket_arn" {
  description = "ARN of the source-data bucket, used to scope the worker's read policy."
  value       = aws_s3_bucket.source.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket."
  value       = aws_s3_bucket.source.bucket_regional_domain_name
}
