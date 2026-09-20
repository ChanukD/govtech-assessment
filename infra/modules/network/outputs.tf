output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "availability_zones" {
  description = "Availability zone names the subnet tiers were placed in."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ. Hosts the ALB only."
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ. Hosts the API and worker tasks."
  value       = [for s in aws_subnet.private : s.id]
}

output "isolated_subnet_ids" {
  description = "Isolated subnet IDs, one per AZ. Hosts the database and has no route off the VPC."
  value       = [for s in aws_subnet.isolated : s.id]
}

output "vpc_endpoints_security_group_id" {
  description = "Security group attached to the interface endpoints. Its ingress rules are owned by the security module."
  value       = aws_security_group.vpc_endpoints.id
}

output "s3_gateway_prefix_list_id" {
  description = "Prefix list of the S3 gateway endpoint. The worker's egress rule targets this rather than a CIDR."
  value       = aws_vpc_endpoint.s3.prefix_list_id
}
