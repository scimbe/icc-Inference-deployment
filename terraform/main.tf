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
   host = "unix:///Users/martin/.colima/default/docker.sock"
}

# Netzwerk für die Container
resource "docker_network" "llm_network" {
  name = "llm-network"
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
    #"OPENAI_API_BASE_URL=http://localhost:8000",
    "OPENAI_API_KEY=${var.tgi_api_key}",
    "ENABLE_RAG_WEB_SEARCH=false",
    "ENABLE_IMAGE_GENERATION=false"
  ]

  ports {
    internal = 8080
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
