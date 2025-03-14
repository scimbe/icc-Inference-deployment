#!/bin/bash

# Konfigurationsdatei für das ICC TGI Deployment mit transformers-Unterstützung
# Kopieren Sie diese Datei nach config.sh und passen Sie die Werte an Ihre Umgebung an

# ICC Namespace (wird automatisch erstellt, normalerweise ist es Ihre w-Kennung + "-default")
# Beispiel: Wenn Ihr Login infwaa123 ist, dann ist Ihr Namespace waa123-default
export NAMESPACE="wXYZ123-default"  # Ersetzen Sie dies mit Ihrem Namespace

# Deployment-Namen
export TGI_DEPLOYMENT_NAME="my-tgi"
export TGI_SERVICE_NAME="my-tgi"
export WEBUI_DEPLOYMENT_NAME="tgi-webui"
export WEBUI_SERVICE_NAME="tgi-webui"

# GPU-Konfiguration
export USE_GPU=true  # Auf false setzen, wenn keine GPU benötigt wird
export GPU_TYPE="gpu-tesla-v100"  # Oder "gpu-tesla-v100s" oder "gpu-tesla-a100" je nach Verfügbarkeit
export GPU_COUNT=1  # Anzahl der GPUs (üblicherweise 1, kann bis zu 4 sein)

# TGI-Konfiguration
# WICHTIG: Falls Sie das Llama-2-Modell verwenden möchten, benötigen Sie ein HuggingFace-Token!
# Andernfalls wählen Sie ein frei zugängliches Modell wie unten vorgeschlagen

# Beispiele für frei zugängliche Modelle:
# export MODEL_NAME="mistralai/Mistral-7B-Instruct-v0.2"  # Frei zugängliches Modell
# export MODEL_NAME="microsoft/phi-2"                     # Kleineres Modell (2.7B)
# export MODEL_NAME="google/gemma-2b-it"                  # Sehr kleines Modell
# export MODEL_NAME="TinyLlama/TinyLlama-1.1B-Chat-v1.0"  # Sehr kleines Modell

# Gated Modelle (benötigen ein HuggingFace-Token):
# export MODEL_NAME="meta-llama/Llama-2-7b-chat-hf"
# export MODEL_NAME="meta-llama/Llama-2-13b-chat-hf"

# Standardmäßig verwenden wir microsoft/phi-2, da recht klein zum testen 
export MODEL_NAME="microsoft/phi-2"

# Hugging Face Token für den Zugriff auf geschützte Modelle
# Wenn Sie Llama-2 oder andere gated Modelle verwenden möchten, geben Sie hier Ihr Token an
# Registrieren Sie sich auf huggingface.co, erstellen Sie ein Token und akzeptieren Sie die Nutzungsbedingungen
# des Modells auf der Modellseite
export HUGGINGFACE_TOKEN=""  # Ihr HuggingFace-Token hier einfügen für gated Models

# Transformers-Konfiguration
export ENABLE_TRANSFORMERS=true  # Aktiviert die Transformers-Integration

# HINWEIS: trust-remote-code ist ein Flag, kein Parameter mit Wert
# Wenn auf true, wird das Flag "--trust-remote-code" gesetzt
# Wenn auf false, wird das Flag nicht gesetzt
export TRUST_REMOTE_CODE=true    # Aktiviert das Flag --trust-remote-code

export TOKENIZERS_PARALLELISM=true  # Beschleunigt die Tokenisierung
export TRANSFORMERS_CACHE="/data/transformers-cache"  # Cache-Pfad für Transformers
export MAX_BATCH_SIZE=8  # Maximale Batch-Größe für Inferenz

# Optional: PEFT-Adapter konfigurieren
# export PEFT_ADAPTER_ID=""      # Pfad oder ID für PEFT-Adapter-Modell

# Optional: Benutzerdefinierte Transformers-Konfiguration als JSON
# export TRANSFORMERS_EXTRA_CONFIG='{"use_cache":true,"attn_implementation":"flash_attention_2"}'

# Modell-Parameter
export QUANTIZATION=""  # Optional: "awq" oder "gptq" für quantisierte Modelle
export GPU_MEMORY_UTILIZATION=0.9  # Anteil des GPU-Speichers, der genutzt werden soll (0.0-1.0)
export MAX_INPUT_LENGTH=4096  # Maximale Eingabe-Länge
export MAX_TOTAL_TOKENS=8192  # Maximale Gesamtlänge (Eingabe + Ausgabe)

# Spezielle Parameter für Tesla A100 GPUs
export DISABLE_FLASH_ATTENTION=false # Auf true setzen, wenn Flash Attention Probleme verursacht
export DSHM_SIZE="8Gi"  # Shared Memory Größe, erhöhe bei Multi-GPU Setups (16Gi für A100)

# API-Konfiguration
export TGI_API_KEY="changeme123"  # API-Schlüssel für TGI

# Ressourcenlimits
export MEMORY_LIMIT="8Gi"  # Speicherlimit, erhöhe auf 64Gi für A100 mit großen Modellen
export CPU_LIMIT="4"  # CPU-Limit

# Zugriffskonfiguration
export CREATE_INGRESS=false  # Auf true setzen, wenn ein Ingress erstellt werden soll
export DOMAIN_NAME="your-domain.informatik.haw-hamburg.de"  # Nur relevant, wenn CREATE_INGRESS=true
