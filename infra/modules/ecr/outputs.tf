output "repository_urls" {
  description = "Repository URLs keyed by logical name, for CI to push to and for task definitions to pull from."
  value       = { for n in var.repository_names : n => "" }
}

output "repository_arns" {
  description = "Repository ARNs keyed by logical name, used to scope the execution roles' pull permissions."
  value       = { for n in var.repository_names : n => "" }
}

output "repository_names" {
  description = "Full repository names keyed by logical name."
  value       = { for n in var.repository_names : n => "" }
}
