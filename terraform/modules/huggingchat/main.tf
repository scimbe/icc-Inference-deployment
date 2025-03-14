
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.0"
    }
  }
}

provider "docker" {
  # macOS
  host = "unix:///Users/dev/.colima/default/docker.sock"
}

# Netzwerk für die Container, falls nicht bereits vorhanden
resource "docker_network" "huggingchat_network" {
  name = var.network_name
  count = var.create_network ? 1 : 0
}

# HuggingChat Container
resource "docker_container" "huggingchat" {
  name  = var.huggingchat_container_name
  image = docker_image.huggingchat.image_id
  
  networks_advanced {
    name = var.network_name
  }

  env = concat([
    "HF_API_URL=http://host.docker.internal:8000",
    "HF_ACCESS_TOKEN=${var.huggingface_token}",
    "DEFAULT_MODEL=${var.model_name}",
    "TGI_API_KEY=${var.tgi_api_key}"
  ], var.additional_env_vars)

  ports {
    internal = 3000
    external = var.huggingchat_external_port
  }

  restart = "unless-stopped"

  volumes {
    container_path = "/data"
    host_path      = var.data_volume_path
    read_only      = false
  }

}

# HuggingChat Image
resource "docker_image" "huggingchat" {
  name = "ghcr.io/huggingface/chat-ui:latest"
}

