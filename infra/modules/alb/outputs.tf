output "arn" {
  description = "ARN of the load balancer."
  value       = aws_lb.main.arn
}

output "arn_suffix" {
  description = "ARN suffix of the load balancer, the form CloudWatch metric dimensions require."
  value       = aws_lb.main.arn_suffix
}

output "dns_name" {
  description = "DNS name of the load balancer. Used as the CloudFront origin for /api/*."
  value       = aws_lb.main.dns_name
}

output "zone_id" {
  description = "Hosted zone ID of the load balancer, for an alias record if a custom domain is added later."
  value       = aws_lb.main.zone_id
}

output "target_group_arn" {
  description = "ARN of the API target group, passed to the API ECS service."
  value       = aws_lb_target_group.api.arn
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the target group, for CloudWatch metric dimensions."
  value       = aws_lb_target_group.api.arn_suffix
}

output "listener_arn" {
  description = "ARN of the listener."
  value       = aws_lb_listener.http.arn
}
