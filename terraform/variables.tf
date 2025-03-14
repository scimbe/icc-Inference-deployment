variable "docker_host" {
  description = "Docker host address (default: use local Docker socket)"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "webui_container_name" {
  description = "Name for the Open WebUI container"
  type        = string
  default     = "open-webui"
}

variable "webui_external_port" {
  description = "External port for Open WebUI"
  type        = number
  default     = 3000
}

variable "deploy_tgi" {
  description = "Whether to deploy TGI container or use an existing one"
  type        = bool
  default     = true
}

variable "tgi_container_name" {
  description = "Name for the TGI container"
  type        = string
  default     = "tgi-server"
}

variable "tgi_external_port" {
  description = "External port for TGI"
  type        = number
  default     = 8000
}

variable "tgi_host" {
  description = "Host address for external TGI server (used if deploy_tgi = false)"
  type        = string
  default     = "tgi-server"
}

variable "tgi_port" {
  description = "Port for external TGI server (used if deploy_tgi = false)"
  type        = number
  default     = 8000
}

variable "model_name" {
  description = "HuggingFace model name or path to use with TGI"
  type        = string
  default     = "microsoft/phi-2"
}

variable "huggingface_token" {
  description = "HuggingFace API token for accessing gated models"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tgi_api_key" {
  description = "API key for TGI OpenAI-compatible API"
  type        = string
  default     = "changeme123"
  sensitive   = true
}

variable "enable_gpu" {
  description = "Whether to enable GPU support for TGI"
  type        = bool
  default     = false
}

variable "data_volume_path" {
  description = "Path on host to store WebUI data"
  type        = string
  default     = "/opt/open-webui/data"
}
