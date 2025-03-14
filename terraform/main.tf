terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.0"
    }
  }
}

provider "docker" {
  host = var.docker_host
}

# Netzwerk für die Container
resource "docker_network" "llm_network" {
  name = "llm-network"
}

# TGI Container
resource "docker_container" "tgi" {
  count = var.deploy_tgi ? 1 : 0
  name  = var.tgi_container_name
  image = docker_image.tgi[0].image_id
  
  networks_advanced {
    name = docker_network.llm_network.name
  }

  command = [
    "--model-id", var.model_name,
    "--port", "8000"
  ]

  dynamic "devices" {
    for_each = var.enable_gpu ? [1] : []
    content {
      host_path      = "/dev/nvidia0"
      container_path = "/dev/nvidia0"
    }
  }

  env = [
    "HUGGING_FACE_HUB_TOKEN=${var.huggingface_token}"
  ]

  ports {
    internal = 8000
    external = var.tgi_external_port
  }

  restart = "unless-stopped"
}

# TGI Image
resource "docker_image" "tgi" {
  count = var.deploy_tgi ? 1 : 0
  name  = "ghcr.io/huggingface/text-generation-inference:latest"
}

# Open WebUI Container
resource "docker_container" "open_webui" {
  name  = var.webui_container_name
  image = docker_image.open_webui.image_id
  
  networks_advanced {
    name = docker_network.llm_network.name
  }

  env = [
    "ENABLE_OLLAMA_API=false",
    "OPENAI_API_BASE_URL=http://${var.deploy_tgi ? docker_container.tgi[0].name : var.tgi_host}:${var.deploy_tgi ? "8000" : var.tgi_port}/v1",
    "OPENAI_API_KEY=${var.tgi_api_key}",
    "ENABLE_RAG_WEB_SEARCH=false",
    "ENABLE_IMAGE_GENERATION=false"
  ]

  ports {
    internal = 3000
    external = var.webui_external_port
  }

  restart = "unless-stopped"

  volumes {
    container_path = "/app/backend/data"
    host_path      = var.data_volume_path
    read_only      = false
  }
}

# Open WebUI Image
resource "docker_image" "open_webui" {
  name = "ghcr.io/open-webui/open-webui:main"
}
