output "huggingchat_url" {
  description = "URL to access HuggingChat"
  value       = "http://localhost:${var.huggingchat_external_port}"
}

output "tgi_api_url" {
  description = "URL to access TGI API"
  value       = var.deploy_tgi ? "http://localhost:${var.tgi_external_port}/v1" : "http://${var.tgi_host}:${var.tgi_port}/v1"
}

output "huggingchat_container_name" {
  description = "Name of the HuggingChat container"
  value       = docker_container.huggingchat.name
}

output "tgi_container_name" {
  description = "Name of the TGI container"
  value       = var.deploy_tgi ? docker_container.tgi[0].name : "external-tgi"
}

output "network_name" {
  description = "Docker network name"
  value       = var.network_name
}