module "open_webui" {
  source = "../../"
  
  # Container names
  webui_container_name = "my-open-webui-gpu"
  tgi_container_name   = "my-tgi-server-gpu"
  
  # Ports
  webui_external_port = 3000
  tgi_external_port   = 8000
  
  # TGI settings with GPU support
  deploy_tgi        = true
  model_name        = "mistralai/Mistral-7B-Instruct-v0.2"
  enable_gpu        = true
  huggingface_token = var.huggingface_token
  
  # Data storage
  data_volume_path = "/opt/open-webui-data"
}

# Define sensitive variable
variable "huggingface_token" {
  description = "HuggingFace API token for accessing models"
  type        = string
  sensitive   = true
}

output "webui_url" {
  value = module.open_webui.webui_url
}

output "tgi_api_url" {
  value = module.open_webui.tgi_api_url
}
