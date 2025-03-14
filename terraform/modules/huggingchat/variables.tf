variable "network_name" {
  description = "Docker network name"
  type        = string
  default     = "huggingchat-network"
}

variable "create_network" {
  description = "Whether to create a new Docker network"
  type        = bool
  default     = true
}

variable "huggingchat_container_name" {
  description = "Name for the HuggingChat container"
  type        = string
  default     = "huggingchat"
}

variable "huggingchat_external_port" {
  description = "External port for HuggingChat"
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

variable "tgi_internal_port" {
  description = "Internal port for TGI"
  type        = number
  default     = 8000
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
  default     = "mistralai/Mistral-7B-Instruct-v0.2"
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
  description = "Path on host to store data"
  type        = string
  default     = "/opt/huggingchat/data"
}

variable "additional_env_vars" {
  description = "Additional environment variables for HuggingChat"
  type        = list(string)
  default     = []
}

variable "additional_tgi_env_vars" {
  description = "Additional environment variables for TGI"
  type        = list(string)
  default     = []
}