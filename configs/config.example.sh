#!/bin/bash

# ICC Namespace (wird automatisch erstellt, normalerweise ist es Ihre w-Kennung + "-default")
# Beispiel: Wenn Ihr Login infwaa123 ist, dann ist Ihr Namespace waa123-default
export NAMESPACE="wXYZ123-default"  # Ersetzen Sie dies mit Ihrem Namespace

# Deployment-Namen
export VLLM_DEPLOYMENT_NAME="my-vllm"
export VLLM_SERVICE_NAME="my-vllm"
export WEBUI_DEPLOYMENT_NAME="vllm-webui"
export WEBUI_SERVICE_NAME="vllm-webui"

# GPU-Konfiguration
export USE_GPU=true  # Auf false setzen, wenn keine GPU benötigt wird
export GPU_TYPE="gpu-tesla-v100"  # Oder "gpu-tesla-v100s" je nach Verfügbarkeit
export GPU_COUNT=1  # Anzahl der GPUs (üblicherweise 1, kann bis zu 4 sein)

# vLLM-Konfiguration
export MODEL_NAME="meta-llama/Llama-2-7b-chat-hf"  # HuggingFace-Modellpfad
export QUANTIZATION=""  # Optional: "awq" oder "gptq" für quantisierte Modelle
export GPU_MEMORY_UTILIZATION=0.9  # Anteil des GPU-Speichers, der genutzt werden soll (0.0-1.0)
export MAX_MODEL_LEN=8192  # Maximale Kontext-Länge
export DTYPE="float16"  # Optional: "float16", "bfloat16" oder "float32"

# API-Konfiguration
export VLLM_API_KEY="changeme123"  # API-Schlüssel für vLLM

# Ressourcenlimits
export MEMORY_LIMIT="16Gi"  # Speicherlimit
export CPU_LIMIT="4"  # CPU-Limit

# Zugriffskonfiguration
export CREATE_INGRESS=false  # Auf true setzen, wenn ein Ingress erstellt werden soll
export DOMAIN_NAME="your-domain.informatik.haw-hamburg.de"  # Nur relevant, wenn CREATE_INGRESS=true
