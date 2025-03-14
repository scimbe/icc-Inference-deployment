# Terraform Module für Open WebUI und TGI mit Docker

Dieses Terraform-Modul ermöglicht die einfache Bereitstellung von Open WebUI zusammen mit oder verbunden zu einem Text Generation Inference (TGI) Server unter Docker.

## Funktionen

- Automatisches Deployment von Open WebUI
- Optional: Deployment des TGI-Servers
- Verbindung zu einem existierenden TGI-Server
- GPU-Unterstützung (optional)
- Persistente Datenspeicherung
- Anpassbare Port-Konfiguration

## Voraussetzungen

- Terraform >= 1.0.0
- Docker Engine
- (Optional) GPU mit NVIDIA-Treibern und NVIDIA Container Toolkit für GPU-Unterstützung

## Grundlegende Verwendung

```hcl
module "open_webui" {
  source = "path/to/terraform-module"
  
  # Container names
  webui_container_name = "my-open-webui"
  tgi_container_name   = "my-tgi-server"
  
  # Ports
  webui_external_port = 3000
  tgi_external_port   = 8000
  
  # TGI settings
  deploy_tgi        = true
  model_name        = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
  huggingface_token = ""  # Optional, für gated models
}
```

## Verbindung zu einem externen TGI-Server

```hcl
module "open_webui" {
  source = "path/to/terraform-module"
  
  # Container configuration
  webui_container_name = "my-open-webui"
  webui_external_port  = 3000
  
  # Connect to external TGI instance
  deploy_tgi  = false
  tgi_host    = "external-tgi-server"
  tgi_port    = 8000
  tgi_api_key = "your-tgi-api-key"
}
```

## GPU-Unterstützung aktivieren

```hcl
module "open_webui" {
  source = "path/to/terraform-module"
  
  # Container names
  webui_container_name = "my-open-webui-gpu"
  tgi_container_name   = "my-tgi-server-gpu"
  
  # TGI settings with GPU support
  deploy_tgi        = true
  model_name        = "mistralai/Mistral-7B-Instruct-v0.2"
  enable_gpu        = true
  huggingface_token = var.huggingface_token
}
```

## Variablen

| Name | Beschreibung | Typ | Standard |
|------|-------------|------|---------|
| `docker_host` | Docker Host Adresse | `string` | `"unix:///var/run/docker.sock"` |
| `webui_container_name` | Name des Open WebUI Containers | `string` | `"open-webui"` |
| `webui_external_port` | Externer Port für Open WebUI | `number` | `3000` |
| `deploy_tgi` | TGI Container deployen? | `bool` | `true` |
| `tgi_container_name` | Name des TGI Containers | `string` | `"tgi-server"` |
| `tgi_external_port` | Externer Port für TGI | `number` | `8000` |
| `tgi_host` | Host-Adresse eines externen TGI-Servers | `string` | `"tgi-server"` |
| `tgi_port` | Port eines externen TGI-Servers | `number` | `8000` |
| `model_name` | HuggingFace-Modellname | `string` | `"microsoft/phi-2"` |
| `huggingface_token` | HuggingFace API Token | `string` | `""` |
| `tgi_api_key` | API-Schlüssel für TGI | `string` | `"changeme123"` |
| `enable_gpu` | GPU-Unterstützung aktivieren? | `bool` | `false` |
| `data_volume_path` | Pfad für persistente Daten | `string` | `"/opt/open-webui/data"` |

## Outputs

| Name | Beschreibung |
|------|-------------|
| `webui_url` | URL zur Open WebUI |
| `tgi_api_url` | URL zur TGI API |
| `webui_container_name` | Name des WebUI Containers |
| `tgi_container_name` | Name des TGI Containers |
| `network_name` | Name des Docker Netzwerks |

## Beispiele

Im `examples/`-Verzeichnis finden sich verschiedene Konfigurationsbeispiele:

- `basic/` - Grundkonfiguration mit Open WebUI und TGI
- `external-tgi/` - Open WebUI mit Verbindung zu einem externen TGI-Server
- `gpu-enabled/` - Konfiguration mit GPU-Unterstützung

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

### WebUI verbindet nicht mit TGI

- Überprüfen Sie, ob WebUI die korrekte TGI-URL verwendet
- Stellen Sie sicher, dass beide Container im selben Netzwerk sind
- Überprüfen Sie, ob der TGI-Server korrekt läuft
