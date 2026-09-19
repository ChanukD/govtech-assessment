output "vpc_id" {
  description = "ID of the VPC."
  value       = ""
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = ""
}

output "availability_zones" {
  description = "Availability zone names the subnet tiers were placed in."
  value       = []
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ. Hosts the ALB only."
  value       = []
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ. Hosts the API and worker tasks."
  value       = []
}

output "isolated_subnet_ids" {
  description = "Isolated subnet IDs, one per AZ. Hosts the database and has no route off the VPC."
  value       = []
}

output "vpc_endpoints_security_group_id" {
  description = "Security group attached to the interface endpoints. Its ingress rules are owned by the security module."
  value       = ""
}
