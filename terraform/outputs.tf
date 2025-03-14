output "webui_url" {
  description = "URL to access Open WebUI"
  value       = "http://localhost:${var.webui_external_port}"
}

output "tgi_api_url" {
  description = "URL to access TGI API"
  value       = var.deploy_tgi ? "http://localhost:${var.tgi_external_port}" : "http://${var.tgi_host}:${var.tgi_port}"
}

output "webui_container_name" {
  description = "Name of the Open WebUI container"
  value       = docker_container.open_webui.name
}

output "tgi_container_name" {
  description = "Name of the TGI container (if deployed)"
  value       = var.deploy_tgi ? docker_container.tgi[0].name : "external TGI server"
}

output "network_name" {
  description = "Docker network name"
  value       = docker_network.llm_network.name
}
