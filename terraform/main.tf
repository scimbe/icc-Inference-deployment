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

# Variable für die Auswahl des UI-Typs
variable "ui_type" {
  description = "Typ der UI (openwebui oder huggingchat)"
  type        = string
  default     = "openwebui"
  
  validation {
    condition     = contains(["openwebui", "huggingchat"], var.ui_type)
    error_message = "Der UI-Typ muss entweder 'openwebui' oder 'huggingchat' sein."
  }
}

# Netzwerk für die Container
resource "docker_network" "llm_network" {
  name = "llm-network"
}

# Open WebUI Container - wenn als UI-Typ ausgewählt
resource "docker_container" "open_webui" {
  count = var.ui_type == "openwebui" ? 1 : 0
  
  name  = var.webui_container_name
  image = docker_image.open_webui[0].image_id
  
  networks_advanced {
    name = docker_network.llm_network.name
  }

  # TGI-Server läuft bereits auf host.docker.internal:8000
  env = [
    "ENABLE_OLLAMA_API=false",
    "OPENAI_API_BASE_URL=http://host.docker.internal:8000/v1",
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

# HuggingChat Container - wenn als UI-Typ ausgewählt
resource "docker_container" "huggingchat" {
  count = var.ui_type == "huggingchat" ? 1 : 0
  
  name  = "${var.webui_container_name}-huggingchat"
  image = docker_image.huggingchat[0].image_id
  
  networks_advanced {
    name = docker_network.llm_network.name
  }

  # TGI-Server läuft bereits auf host.docker.internal:8000
  env = [
    "HF_API_URL=http://host.docker.internal:8000/v1",
    "DEFAULT_MODEL=${var.model_name}",
    "HF_ACCESS_TOKEN=${var.huggingface_token}",
    "ENABLE_EXPERIMENTAL_FEATURES=true",
    "ENABLE_THEMING=true"
  ]

  ports {
    internal = 3000
    external = var.webui_external_port
  }

  restart = "unless-stopped"

  volumes {
    container_path = "/data"
    host_path      = "${var.data_volume_path}/huggingchat"
    read_only      = false
  }
}

# Open WebUI Image
resource "docker_image" "open_webui" {
  count = var.ui_type == "openwebui" ? 1 : 0
  name  = "ghcr.io/open-webui/open-webui:main"
}

# HuggingChat Image
resource "docker_image" "huggingchat" {
  count = var.ui_type == "huggingchat" ? 1 : 0
  name  = "ghcr.io/huggingface/chat-ui:latest"
}