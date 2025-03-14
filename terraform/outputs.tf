output "webui_url" {
  description = "URL to access Open WebUI or HuggingChat"
  value       = "http://localhost:${var.webui_external_port}"
}

output "ui_type" {
  description = "Type of UI deployed (openwebui or huggingchat)"
  value       = var.ui_type
}

output "network_name" {
  description = "Docker network name"
  value       = docker_network.llm_network.name
}

output "container_name" {
  description = "Name of the deployed container"
  value       = var.ui_type == "openwebui" ? (length(docker_container.open_webui) > 0 ? docker_container.open_webui[0].name : "") : (length(docker_container.huggingchat) > 0 ? docker_container.huggingchat[0].name : "")
}