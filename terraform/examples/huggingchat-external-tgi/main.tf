module "huggingchat" {
  source = "../../modules/huggingchat"
  
  # Container configuration
  huggingchat_container_name = "my-huggingchat"
  huggingchat_external_port  = 3000
  
  # Connect to external TGI instance
  deploy_tgi  = false
  tgi_host    = "external-tgi-server.example.com"  # Use hostname or IP of external TGI server
  tgi_port    = 8000
  tgi_api_key = "your-tgi-api-key"
  
  # Model configuration
  model_name        = "mistralai/Mistral-7B-Instruct-v0.2"
  huggingface_token = var.huggingface_token
  
  # Data storage
  data_volume_path = "/tmp/huggingchat-data"
}

# Define sensitive variable
variable "huggingface_token" {
  description = "HuggingFace API token for accessing models"
  type        = string
  sensitive   = true
  default     = ""
}

output "huggingchat_url" {
  value = module.huggingchat.huggingchat_url
}

output "tgi_api_url" {
  value = module.huggingchat.tgi_api_url
}