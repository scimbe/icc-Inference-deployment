output "webui_url" {
  description = "URL to access Open WebUI"
  value       = "http://localhost:${var.webui_external_port}"
}


output "network_name" {
  description = "Docker network name"
  value       = docker_network.llm_network.name
}
