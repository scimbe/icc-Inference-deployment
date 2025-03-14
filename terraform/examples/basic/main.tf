module "open_webui" {
  source = "../../"
  
  # Container names
  webui_container_name = "my-open-webui"
  tgi_container_name   = "my-tgi-server"
  
  # Ports
  webui_external_port = 3000
  tgi_external_port   = 8000
  
  # TGI settings
  deploy_tgi       = true
  model_name       = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
  enable_gpu       = false
  huggingface_token = ""
  
  # Data storage
  data_volume_path = "/tmp/open-webui-data"
}

output "webui_url" {
  value = module.open_webui.webui_url
}

output "tgi_api_url" {
  value = module.open_webui.tgi_api_url
}
