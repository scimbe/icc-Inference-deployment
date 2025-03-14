terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.0"
    }
  }
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
    "HF_API_URL=${var.deploy_tgi ? "http://${var.tgi_container_name}:${var.tgi_internal_port}/v1" : "http://${var.tgi_host}:${var.tgi_port}/v1"}",
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

  depends_on = [
    var.deploy_tgi ? docker_container.tgi[0] : null
  ]
}

# HuggingChat Image
resource "docker_image" "huggingchat" {
  name = "ghcr.io/huggingface/chat-ui:latest"
}

# TGI Container (optional)
resource "docker_container" "tgi" {
  count = var.deploy_tgi ? 1 : 0
  
  name  = var.tgi_container_name
  image = docker_image.tgi[0].image_id
  
  networks_advanced {
    name = var.network_name
  }

  command = [
    "--model-id=${var.model_name}",
    "--port=${var.tgi_internal_port}"
  ]

  env = concat([
    "HF_TOKEN=${var.huggingface_token}",
    "HUGGING_FACE_HUB_TOKEN=${var.huggingface_token}"
  ], var.enable_gpu ? ["CUDA_VISIBLE_DEVICES=0"] : [], var.additional_tgi_env_vars)

  ports {
    internal = var.tgi_internal_port
    external = var.tgi_external_port
  }

  restart = "unless-stopped"

  # GPU-Unterstützung hinzufügen, wenn aktiviert
  dynamic "devices" {
    for_each = var.enable_gpu ? [1] : []
    content {
      host_path      = "/dev/nvidia0"
      container_path = "/dev/nvidia0"
    }
  }

  # Shared memory erhöhen für bessere Performance
  shm_size = var.enable_gpu ? 1024 : 256

  volumes {
    container_path = "/data"
    host_path      = "${var.data_volume_path}/tgi-models"
    read_only      = false
  }
}

# TGI Image
resource "docker_image" "tgi" {
  count = var.deploy_tgi ? 1 : 0
  name  = "ghcr.io/huggingface/text-generation-inference:latest"
}