output "profile" {
  value = var.profile
}

output "endpoint" {
  description = "OpenAI-compatible endpoint, through the NodePort that kind publishes on localhost."
  value       = "http://localhost:8080/v1"
}
