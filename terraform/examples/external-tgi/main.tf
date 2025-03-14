module "open_webui" {
  source = "../../"
  
  # Container configuration
  webui_container_name = "my-open-webui"
  webui_external_port  = 3000
  
  # Connect to external TGI instance
  deploy_tgi = false
  tgi_host   = "external-tgi-server.example.com"  # Use hostname or IP of external TGI server
  tgi_port   = 8000
  tgi_api_key = "your-tgi-api-key"
  
  # Data storage
  data_volume_path = "/tmp/open-webui-data"
}

output "webui_url" {
  value = module.open_webui.webui_url
}

output "tgi_api_url" {
  value = module.open_webui.tgi_api_url
}
