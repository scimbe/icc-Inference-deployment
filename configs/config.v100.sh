#!/bin/bash

# Beispielkonfigurationsdatei für das ICC TGI Deployment - V100 Optimiert
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
export GPU_TYPE="gpu-tesla-v100"  # Tesla V100 GPUs
export GPU_COUNT=1  # Anzahl der GPUs (üblicherweise 1, kann bis zu 4 sein)

# TGI-Konfiguration
# WICHTIG: Falls Sie das Llama-2-Modell verwenden möchten, benötigen Sie ein HuggingFace-Token!
# Andernfalls wählen Sie ein frei zugängliches Modell wie unten vorgeschlagen

# Für V100 empfohlene Modelle:
export MODEL_NAME="NousResearch/Hermes-3-Llama-3.1-8B"  # Sehr kleines Modell zum Testen
# export MODEL_NAME="microsoft/phi-2"                     # Kleineres Modell (2.7B)
# export MODEL_NAME="google/gemma-2b-it"                  # Sehr kleines Modell
# export MODEL_NAME="mistralai/Mistral-7B-Instruct-v0.2"  # Frei zugängliches Modell

# Hugging Face Token für den Zugriff auf geschützte Modelle
# Wenn Sie Llama-2 oder andere gated Modelle verwenden möchten, geben Sie hier Ihr Token an
# Registrieren Sie sich auf huggingface.co, erstellen Sie ein Token und akzeptieren Sie die Nutzungsbedingungen
# des Modells auf der Modellseite
export HUGGINGFACE_TOKEN=""  # Ihr HuggingFace-Token hier einfügen für gated Models

# Memory-Optimierungen für V100
# WICHTIG: Wählen Sie ENTWEDER Quantisierung ODER dtype, aber nicht beides gleichzeitig!
# Option 1: Quantisierung (empfohlen für größere Modelle)
# export QUANTIZATION="awq"  # Aktiviere AWQ-Quantisierung für bessere Memory-Effizienz
# Option 2: Setzen Sie dtype (nutzen Sie dies nur wenn keine Quantisierung aktiv ist)
# export QUANTIZATION=""     # Dies muss leer sein, wenn dtype verwendet werden soll!

# Gemeinsame Performance-Parameter
export CUDA_MEMORY_FRACTION=0.85  # Korrigierter Parameter für TGI 1.2.0
export MAX_INPUT_LENGTH=2048  # Reduzierte maximale Eingabelänge für V100
export MAX_TOTAL_TOKENS=4096  # Reduzierte Gesamtlänge (Eingabe + Ausgabe)
export MAX_BATCH_PREFILL_TOKENS=4096  # Begrenzung der Batch-Größe beim Prefill

# Erweiterte Konfiguration für V100
export DSHM_SIZE="8Gi"  # Shared Memory Größe (wichtig für Multi-GPU)

# API-Konfiguration
export TGI_API_KEY="changeme123"  # API-Schlüssel für TGI

# Ressourcenlimits für V100
export MEMORY_LIMIT="16Gi"  # Speicherlimit, für Multi-GPU auf 24Gi erhöhen
export CPU_LIMIT="4"  # CPU-Limit

# Zugriffskonfiguration
export CREATE_INGRESS=false  # Auf true setzen, wenn ein Ingress erstellt werden soll
export DOMAIN_NAME="your-domain.informatik.haw-hamburg.de"  # Nur relevant, wenn CREATE_INGRESS=true
