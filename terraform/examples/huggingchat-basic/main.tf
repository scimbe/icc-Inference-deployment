module "huggingchat" {
  source = "../../modules/huggingchat"
  
  # Container names
  huggingchat_container_name = "my-huggingchat"
  tgi_container_name         = "my-tgi-server"
  
  # Ports
  huggingchat_external_port = 3000
  tgi_external_port         = 8000
  
  # TGI settings
  deploy_tgi       = true
  model_name       = "TinyLlama/TinyLlama-1.1B-Chat-v1.0" # Kleines Modell für Tests
  enable_gpu       = false
  huggingface_token = "" # Kein Token für öffentliche Modelle notwendig
  
  # Data storage
  data_volume_path = "/tmp/huggingchat-data"
}

output "huggingchat_url" {
  value = module.huggingchat.huggingchat_url
}

output "tgi_api_url" {
  value = module.huggingchat.tgi_api_url
}