# The generated password is deliberately absent from this list. It is written to
# Secrets Manager and read from there at task start; nothing outputs it.

output "endpoint" {
  description = "Connection endpoint in host:port form."
  value       = ""
  sensitive   = true
}

output "address" {
  description = "Hostname of the instance."
  value       = ""
  sensitive   = true
}

output "port" {
  description = "Port the instance listens on."
  value       = 0
}

output "db_name" {
  description = "Name of the initial database."
  value       = ""
}

output "instance_identifier" {
  description = "Instance identifier, the form CloudWatch metric dimensions require."
  value       = ""
}

output "instance_arn" {
  description = "ARN of the database instance."
  value       = ""
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding the credentials. The secret value itself is never exposed."
  value       = ""
  sensitive   = true
}
