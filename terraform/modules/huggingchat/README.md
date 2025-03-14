# Terraform Module für HuggingChat mit TGI

Dieses Terraform-Modul ermöglicht die einfache Bereitstellung von HuggingChat zusammen mit oder verbunden zu einem Text Generation Inference (TGI) Server unter Docker.

## Funktionen

- Automatisches Deployment von HuggingChat
- Optional: Deployment des TGI-Servers
- Verbindung zu einem existierenden TGI-Server
- GPU-Unterstützung (optional)
- Persistente Datenspeicherung
- Anpassbare Port-Konfiguration
- IntelliJ IDEA MCP Integration

## Voraussetzungen

- Terraform >= 1.0.0
- Docker Engine
- IntelliJ IDEA mit Multi-Cloud Platform Plugin
- (Optional) GPU mit NVIDIA-Treibern und NVIDIA Container Toolkit für GPU-Unterstützung

## Grundlegende Verwendung

```hcl
module "huggingchat" {
  source = "path/to/terraform-module/modules/huggingchat"
  
  # Container names
  huggingchat_container_name = "my-huggingchat"
  tgi_container_name         = "my-tgi-server"
  
  # Ports
  huggingchat_external_port = 3000
  tgi_external_port         = 8000
  
  # TGI settings
  deploy_tgi        = true
  model_name        = "mistralai/Mistral-7B-Instruct-v0.2"
  huggingface_token = var.huggingface_token
}
```

## Verbindung zu einem externen TGI-Server

```hcl
module "huggingchat" {
  source = "path/to/terraform-module/modules/huggingchat"
  
  # Container configuration
  huggingchat_container_name = "my-huggingchat"
  huggingchat_external_port  = 3000
  
  # Connect to external TGI instance
  deploy_tgi  = false
  tgi_host    = "external-tgi-server"
  tgi_port    = 8000
  tgi_api_key = "your-tgi-api-key"
}
```

## GPU-Unterstützung aktivieren

```hcl
module "huggingchat" {
  source = "path/to/terraform-module/modules/huggingchat"
  
  # Container names
  huggingchat_container_name = "my-huggingchat-gpu"
  tgi_container_name         = "my-tgi-server-gpu"
  
  # TGI settings with GPU support
  deploy_tgi        = true
  model_name        = "mistralai/Mistral-7B-Instruct-v0.2"
  enable_gpu        = true
  huggingface_token = var.huggingface_token
}
```

## IntelliJ IDEA MCP Integration

1. Öffnen Sie IntelliJ IDEA mit installiertem MCP Plugin
2. Wählen Sie "File" > "New" > "Project"
3. Wählen Sie "Terraform" als Projekttyp
4. Importieren Sie dieses Modul
5. Konfigurieren Sie Ihre Terraform-Variablen
6. Führen Sie `terraform init` und `terraform apply` aus

## Variablen

| Name | Beschreibung | Typ | Standard |
|------|-------------|------|---------|
| `network_name` | Docker-Netzwerkname | `string` | `"huggingchat-network"` |
| `create_network` | Docker-Netzwerk erstellen? | `bool` | `true` |
| `huggingchat_container_name` | Name des HuggingChat Containers | `string` | `"huggingchat"` |
| `huggingchat_external_port` | Externer Port für HuggingChat | `number` | `3000` |
| `deploy_tgi` | TGI Container deployen? | `bool` | `true` |
| `tgi_container_name` | Name des TGI Containers | `string` | `"tgi-server"` |
| `tgi_internal_port` | Interner Port für TGI | `number` | `8000` |
| `tgi_external_port` | Externer Port für TGI | `number` | `8000` |
| `tgi_host` | Host-Adresse eines externen TGI-Servers | `string` | `"tgi-server"` |
| `tgi_port` | Port eines externen TGI-Servers | `number` | `8000` |
| `model_name` | HuggingFace-Modellname | `string` | `"mistralai/Mistral-7B-Instruct-v0.2"` |
| `huggingface_token` | HuggingFace API Token | `string` | `""` |
| `tgi_api_key` | API-Schlüssel für TGI | `string` | `"changeme123"` |
| `enable_gpu` | GPU-Unterstützung aktivieren? | `bool` | `false` |
| `data_volume_path` | Pfad für persistente Daten | `string` | `"/opt/huggingchat/data"` |
| `additional_env_vars` | Zusätzliche Umgebungsvariablen für HuggingChat | `list(string)` | `[]` |
| `additional_tgi_env_vars` | Zusätzliche Umgebungsvariablen für TGI | `list(string)` | `[]` |

## Outputs

| Name | Beschreibung |
|------|-------------|
| `huggingchat_url` | URL zur HuggingChat-Oberfläche |
| `tgi_api_url` | URL zur TGI API |
| `huggingchat_container_name` | Name des HuggingChat Containers |
| `tgi_container_name` | Name des TGI Containers |
| `network_name` | Name des Docker Netzwerks |

## Hinweise

- Für GPU-Unterstützung muss das NVIDIA Container Toolkit installiert sein
- Für einige Modelle wird ein HuggingFace-Token benötigt
- Die Container-Namen müssen innerhalb einer Docker-Instanz eindeutig sein

## Troubleshooting

### TGI startet nicht

Überprüfen Sie die Container-Logs:

```
docker logs my-tgi-server
```

Bei GPU-bezogenen Problemen, überprüfen Sie die GPU-Zugänglichkeit:

```
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

### HuggingChat verbindet nicht mit TGI

- Überprüfen Sie, ob HuggingChat die korrekte TGI-URL verwendet
- Stellen Sie sicher, dass beide Container im selben Netzwerk sind
- Überprüfen Sie, ob der TGI-Server korrekt läuft