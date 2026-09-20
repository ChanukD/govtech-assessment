output "arn" {
  description = "ARN of the load balancer."
  value       = ""
}

output "arn_suffix" {
  description = "ARN suffix of the load balancer, the form CloudWatch metric dimensions require."
  value       = ""
}

output "dns_name" {
  description = "DNS name of the load balancer. Used as the CloudFront origin for /api/*."
  value       = ""
}

output "zone_id" {
  description = "Hosted zone ID of the load balancer, for an alias record if a custom domain is added later."
  value       = ""
}

output "target_group_arn" {
  description = "ARN of the API target group, passed to the API ECS service."
  value       = ""
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the target group, for CloudWatch metric dimensions."
  value       = ""
}

output "listener_arn" {
  description = "ARN of the listener."
  value       = ""
}
