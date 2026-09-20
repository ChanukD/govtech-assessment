# The generated password is deliberately absent from this list. It is written to
# Secrets Manager and read from there at task start; nothing outputs it.

output "endpoint" {
  description = "Connection endpoint in host:port form."
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "address" {
  description = "Hostname of the instance."
  value       = aws_db_instance.main.address
  sensitive   = true
}

output "port" {
  description = "Port the instance listens on."
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.main.db_name
}

output "instance_identifier" {
  description = "Instance identifier, the form CloudWatch metric dimensions require."
  value       = aws_db_instance.main.identifier
}

output "instance_arn" {
  description = "ARN of the database instance."
  value       = aws_db_instance.main.arn
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding the credentials. The secret value itself is never exposed."
  value       = aws_secretsmanager_secret.db.arn
  sensitive   = true
}
