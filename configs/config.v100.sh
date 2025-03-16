#!/bin/bash

# ===================================================================
# ICC LLM Deployment - V100 GPU Optimierte Konfiguration
# ===================================================================
# Diese Konfiguration ist speziell für Tesla V100 GPUs optimiert
# Unterstützt sowohl TGI als auch vLLM Deployments
# ===================================================================

# ===== GRUNDKONFIGURATION (MUSS ANGEPASST WERDEN) =====

# ICC Namespace (Ihre w-Kennung + "-default")
# z.B. Bei Login "infwaa123" wäre der Namespace "waa123-default"
export NAMESPACE="wXYZ123-default"  # ⚠️ UNBEDINGT ANPASSEN!

# HuggingFace Token (nur für geschützte Modelle wie Llama)
# Registrieren Sie sich auf huggingface.co und generieren Sie ein Token
export HUGGINGFACE_TOKEN=""         # Optional, für gated Modelle

# ===== DEPLOYMENT-KONFIGURATION =====

# Engine-Auswahl
export ENGINE_TYPE="tgi"            # "tgi" oder "vllm"

# Deployment-Namen
export TGI_DEPLOYMENT_NAME="inf-server"
export TGI_SERVICE_NAME="tgi-service"
export WEBUI_DEPLOYMENT_NAME="llm-webui" 
export WEBUI_SERVICE_NAME="llm-webui"

# ===== GPU-KONFIGURATION =====

# GPU-Einstellungen
export USE_GPU=true                 # true/false: GPU-Unterstützung aktivieren/deaktivieren
export GPU_TYPE="gpu-tesla-v100"    # GPU-Typ auf der ICC
export GPU_COUNT=1                  # Anzahl der GPUs (1-4)

# ===== MODELL-KONFIGURATION =====

# Modellauswahl (einen der folgenden Werte verwenden)
export MODEL_NAME="TinyLlama/TinyLlama-1.1B-Chat-v1.0"  # Mini-Modell für Tests

# Empfohlene Modelle nach Größe:
# - Klein (~2B Parameter):
#   export MODEL_NAME="microsoft/phi-2"
#   export MODEL_NAME="google/gemma-2b"
# 
# - Mittel (~7B Parameter):
#   export MODEL_NAME="mistralai/Mistral-7B-Instruct-v0.2"
#   export MODEL_NAME="NousResearch/Hermes-3-Llama-3.1-8B"
# 
# - Größere Modelle nur mit Quantisierung oder Multi-GPU (13-70B)

# ===== MEMORY-OPTIMIERUNG =====

# WÄHLEN SIE EINE DER BEIDEN OPTIONEN:

# OPTION 1: Nutzen Sie Quantisierung für größere Modelle (empfohlen für 7B+)
# export QUANTIZATION="awq"  # Aktiviere AWQ-Quantisierung für bessere Memory-Effizienz

# OPTION 2: Verwenden Sie Float16-Precision (Default, wenn Quantisierung leer)
export QUANTIZATION=""      # Leer lassen, um float16 zu verwenden

# ===== TGI-SPEZIFISCHE PARAMETER =====

# Performance-Parameter
export CUDA_MEMORY_FRACTION=0.85    # GPU-Speichernutzung (optimal für V100)
export MAX_INPUT_LENGTH=2048        # Eingabe-Kontextlänge
export MAX_TOTAL_TOKENS=4096        # Eingabe + Ausgabe Tokens
export MAX_BATCH_PREFILL_TOKENS=4096 # Batch-Größenbegrenzung

# ===== vLLM-SPEZIFISCHE PARAMETER =====

# Performance-Parameter für vLLM
export BLOCK_SIZE=16                # GPU Memory Block-Größe
export SWAP_SPACE=4                 # Swap-Space in GB
export MAX_BATCH_SIZE=32            # Maximale Batch-Größe (Hinweis: dieser Parameter wird von neueren vLLM-Versionen möglicherweise nicht unterstützt)

# ===== RESSOURCEN-KONFIGURATION =====

# Speichereinstellungen
export DSHM_SIZE="8Gi"              # Shared Memory (für Multi-GPU erhöhen)
export MEMORY_LIMIT="16Gi"          # Container RAM-Limit 
export CPU_LIMIT="4"                # CPU-Cores

# ===== ZUGRIFFSKONFIGURATION =====

# API-Sicherheit
export TGI_API_KEY="changeme123"    # API-Schlüssel (leer = keine Authentifizierung)

# Ingress (extern erreichbar machen)
export CREATE_INGRESS=false         # Auf true setzen für externen Zugriff
export DOMAIN_NAME="ihr-name.informatik.haw-hamburg.de"  # Nur bei CREATE_INGRESS=true