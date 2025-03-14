output "integration_url" {
  description = "URL to access IntelliJ integration"
  value       = "http://localhost:${var.intellij_integration_port}"
}

output "huggingchat_url" {
  description = "URL to access HuggingChat"
  value       = var.deploy_huggingchat ? module.huggingchat[0].huggingchat_url : var.huggingchat_external_url
}

output "tgi_api_url" {
  description = "URL to access TGI API"
  value       = var.deploy_huggingchat && var.deploy_tgi ? module.huggingchat[0].tgi_api_url : var.tgi_external_url
}

output "integration_container_name" {
  description = "Name of the IntelliJ integration container"
  value       = docker_container.intellij_integration.name
}

output "huggingchat_container_name" {
  description = "Name of the HuggingChat container"
  value       = var.deploy_huggingchat ? module.huggingchat[0].huggingchat_container_name : "external-huggingchat"
}

output "tgi_container_name" {
  description = "Name of the TGI container"
  value       = var.deploy_huggingchat && var.deploy_tgi ? module.huggingchat[0].tgi_container_name : "external-tgi"
}

output "network_name" {
  description = "Docker network name"
  value       = var.deploy_huggingchat ? module.huggingchat[0].network_name : var.network_name
}