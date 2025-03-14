terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.0"
    }
  }
}

variable "nginx_config_path" {
  default = "/Users/dev/Documents/git/icc/icc-tgi-deployment/terraform/nginx.conf"
}

provider "docker" {
  # macOS
  host = "unix:///Users/dev/.colima/default/docker.sock"
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
    "OPENAI_API_BASE_URL=http://nginx:8000",  # Nginx als API-Gateway nutzen
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

# Nginx Container (API-Rewrite von /v1/completions -> /generate)
resource "docker_container" "nginx" {
  name  = "nginx-proxy"
  image = docker_image.nginx.image_id

  networks_advanced {
    name = docker_network.llm_network.name
  }

  restart = "unless-stopped"

  volumes {
    container_path = "/etc/nginx/nginx.conf"
    host_path      = var.nginx_config_path
    read_only      = true
  }

  ports {
    internal = 8000
    external = 8000
  }
}

# Nginx Image
resource "docker_image" "nginx" {
  name = "nginx:latest"
}
