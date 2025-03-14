module "huggingchat" {
  source = "../../modules/huggingchat"
  
  # Container names
  huggingchat_container_name = "my-huggingchat-gpu"
  tgi_container_name         = "my-tgi-server-gpu"
  
  # Ports
  huggingchat_external_port = 3000
  tgi_external_port         = 8000
  
  # TGI settings with GPU support
  deploy_tgi        = true
  model_name        = "mistralai/Mistral-7B-Instruct-v0.2"
  enable_gpu        = true
  huggingface_token = var.huggingface_token
  
  # Data storage
  data_volume_path = "/opt/huggingchat-data"
  
  # GPU-spezifische Umgebungsvariablen
  additional_tgi_env_vars = [
    "CUDA_MEMORY_FRACTION=0.9",
    "NCCL_DEBUG=INFO"
  ]
}

# Define sensitive variable
variable "huggingface_token" {
  description = "HuggingFace API token for accessing models"
  type        = string
  sensitive   = true
}

output "huggingchat_url" {
  value = module.huggingchat.huggingchat_url
}

output "tgi_api_url" {
  value = module.huggingchat.tgi_api_url
}