#!/bin/bash
# ============================================================================
# TGI Deployment Script für V100 GPUs
# ============================================================================
# Autor: HAW Hamburg ICC Team
# Version: 2.0.0
# 
# Dieses Skript erstellt ein optimiertes Text Generation Inference Deployment
# mit V100-spezifischen Einstellungen auf der ICC Kubernetes-Plattform.
# ============================================================================

set -eo pipefail

# ============================================================================
# Funktionen
# ============================================================================

# Fehlerbehandlung
function error() {
    echo -e "\e[31mFEHLER: $1\e[0m" >&2
    exit 1
}

# Info-Ausgabe
function info() {
    echo -e "\e[34m$1\e[0m"
}

# Erfolgs-Ausgabe
function success() {
    echo -e "\e[32m$1\e[0m"
}

# Warnung-Ausgabe
function warn() {
    echo -e "\e[33m$1\e[0m"
}

# Konfiguration laden
function load_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        error "Konfigurationsdatei nicht gefunden: $config_file
       Bitte kopieren Sie configs/config.v100.sh nach configs/config.sh und passen Sie die Werte an."
    fi
    
    # shellcheck source=/dev/null
    source "$config_file"
    
    # Prüfe kritische Konfigurationsvariablen
    [[ -z "$NAMESPACE" ]] && error "NAMESPACE ist nicht konfiguriert in $config_file"
    
    # Setze Standardwerte für optionale Parameter
    MODEL_NAME="${MODEL_NAME:-TinyLlama/TinyLlama-1.1B-Chat-v1.0}"
    USE_GPU="${USE_GPU:-true}"
    GPU_COUNT="${GPU_COUNT:-1}"
    GPU_TYPE="${GPU_TYPE:-gpu-tesla-v100}"
    CUDA_MEMORY_FRACTION="${CUDA_MEMORY_FRACTION:-0.85}"
    MAX_INPUT_LENGTH="${MAX_INPUT_LENGTH:-2048}"
    MAX_TOTAL_TOKENS="${MAX_TOTAL_TOKENS:-4096}"
    MAX_BATCH_PREFILL_TOKENS="${MAX_BATCH_PREFILL_TOKENS:-4096}"
    DSHM_SIZE="${DSHM_SIZE:-8Gi}"
    MEMORY_LIMIT="${MEMORY_LIMIT:-16Gi}"
    CPU_LIMIT="${CPU_LIMIT:-4}"
    TGI_DEPLOYMENT_NAME="${TGI_DEPLOYMENT_NAME:-tgi-server}"
    TGI_SERVICE_NAME="${TGI_SERVICE_NAME:-tgi-service}"

    # Dynamische Anpassung von dshm basierend auf GPU-Anzahl
    if [[ "$USE_GPU" == "true" ]] && [[ "$GPU_COUNT" -gt 1 ]]; then
        # Erhöhe dshm proportional zur GPU-Anzahl
        DSHM_SIZE="$((8 * GPU_COUNT))Gi"
        info "Multi-GPU-Setup: dshm auf $DSHM_SIZE erhöht"
    fi

    # Standard NCCL-Umgebungsvariablen, falls nicht definiert
    NCCL_DEBUG="${NCCL_DEBUG:-INFO}"
    NCCL_DEBUG_SUBSYS="${NCCL_DEBUG_SUBSYS:-ALL}"
    NCCL_P2P_DISABLE="${NCCL_P2P_DISABLE:-0}"
    NCCL_IB_DISABLE="${NCCL_IB_DISABLE:-0}"
    NCCL_P2P_LEVEL="${NCCL_P2P_LEVEL:-NVL}"
    NCCL_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME:-^lo,docker}"
    NCCL_SHM_DISABLE="${NCCL_SHM_DISABLE:-0}"
}

# Modell-Zugriff prüfen
function check_model_access() {
    local model="$1"
    local token="$2"
    
    local gated_models=("meta-llama/Llama-2" "meta-llama/Llama-3" "mistralai/Mixtral" "meta-llama/Meta-Llama")
    
    for gated_prefix in "${gated_models[@]}"; do
        if [[ "$model" == *"$gated_prefix"* ]] && [[ -z "$token" ]]; then
            warn "WARNUNG: Das Modell '$model' ist möglicherweise ein gated Model und erfordert ein HuggingFace-Token."
            warn "Falls der Zugriff fehlschlägt, setzen Sie HUGGINGFACE_TOKEN in config.sh oder wählen Sie ein freies Modell."
            return 0
        fi
    done
    return 0
}

# CUDA Devices-String generieren
function prepare_cuda_devices() {
    local count="$1"
    local devices="0"
    
    if [[ "$USE_GPU" == "true" ]] && [[ "$count" -gt 1 ]]; then
        for ((i=1; i<count; i++)); do
            devices="${devices},$i"
        done
        info "Multi-GPU Konfiguration: $count GPUs (CUDA Devices: $devices)"
    else
        info "Single-GPU Konfiguration"
    fi
    
    echo "$devices"
}

# Alte Ressourcen entfernen
function cleanup_resources() {
    local namespace="$1"
    local deployment="$2"
    local service="$3"
    
    info "Entferne bestehende Ressourcen..."
    kubectl -n "$namespace" delete deployment "$deployment" --ignore-not-found=true
    kubectl -n "$namespace" delete service "$service" --ignore-not-found=true
    
    # Warte kurz, damit Kubernetes Zeit hat, alles zu bereinigen
    sleep 3
}

# Secret erstellen, falls Token vorhanden
function create_huggingface_secret() {
    local namespace="$1"
    local token="$2"
    
    if [[ -z "$token" ]]; then
        warn "Kein HuggingFace-Token konfiguriert (nur für freie Modelle geeignet)"
        return 0
    fi
    
    local token_base64
    token_base64=$(echo -n "$token" | base64)
    success "HuggingFace-Token konfiguriert ✓"
    
    kubectl -n "$namespace" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: huggingface-token
  namespace: ${namespace}
type: Opaque
data:
  token: ${token_base64}
EOF
}

# Secret für API-Schlüssel erstellen
function create_api_key_secret() {
    local namespace="$1"
    local api_key="$2"
    
    if [[ -z "$api_key" ]]; then
        warn "Kein TGI API-Key konfiguriert. Die API ist nicht geschützt!"
        return 0
    fi
    
    local key_base64
    key_base64=$(echo -n "$api_key" | base64)
    success "TGI API-Key konfiguriert ✓"
    
    kubectl -n "$namespace" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: tgi-api-key
  namespace: ${namespace}
type: Opaque
data:
  token: ${key_base64}
EOF
}

# Manifest generieren
function generate_tgi_manifest() {
    local namespace="$1"
    local deployment_name="$2"
    local service_name="$3"
    local model="$4"
    local cuda_devices="$5"
    local quantization="$6"
    local gpu_count="$7"
    local gpu_type="$8"
    local hf_token="$9"
    local api_key="${10}"
    local output_file="${11}"
    
    # Bedingungen für Features
    local use_sharded=false
    [[ "$USE_GPU" == "true" ]] && [[ "$gpu_count" -gt 1 ]] && use_sharded=true
    
    # Erstelle Manifest
    cat > "$output_file" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${deployment_name}
  namespace: ${namespace}
  labels:
    app: llm-server
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: llm-server
  template:
    metadata:
      labels:
        app: llm-server
    spec:
      tolerations:
      - key: "${gpu_type}"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: tgi
        image: ghcr.io/huggingface/text-generation-inference:latest
        imagePullPolicy: IfNotPresent
        command:
        - "text-generation-launcher"
        args:
        - "--model-id=${model}"
        - "--port=8000"
EOF

    # Quantisierung oder Dtype (nicht beides)
    if [[ -n "$quantization" ]]; then
        cat >> "$output_file" << EOF
        - "--quantize=${quantization}"
EOF
    else
        cat >> "$output_file" << EOF
        - "--dtype=float16"
EOF
    fi

    # V100-optimierte Parameter
    cat >> "$output_file" << EOF
        - "--max-input-length=${MAX_INPUT_LENGTH}"
        - "--max-total-tokens=${MAX_TOTAL_TOKENS}"
        - "--max-batch-prefill-tokens=${MAX_BATCH_PREFILL_TOKENS}"
        - "--cuda-memory-fraction=${CUDA_MEMORY_FRACTION}"
EOF

    # Berechne optimale Anzahl von parallelen Anfragen basierend auf GPU-Anzahl
    local max_concurrent=$((8 * (gpu_count > 0 ? gpu_count : 1)))
    cat >> "$output_file" << EOF
        - "--max-concurrent-requests=${max_concurrent}"
EOF

    # Multi-GPU Unterstützung
    if [[ "$use_sharded" == true ]]; then
        cat >> "$output_file" << EOF
        - "--sharded=true"
        - "--num-shard=${gpu_count}"
EOF
        # Optimierte Parameter für Multi-GPU
        local workers=$(( gpu_count > 2 ? gpu_count : 2 ))
        cat >> "$output_file" << EOF
        - "--max-parallel-loading-workers=${workers}"
EOF
    fi

    # Umgebungsvariablen
    cat >> "$output_file" << EOF
        env:
        - name: CUDA_VISIBLE_DEVICES
          value: "${cuda_devices}"
        - name: NCCL_DEBUG
          value: "${NCCL_DEBUG}"
        - name: NCCL_DEBUG_SUBSYS
          value: "${NCCL_DEBUG_SUBSYS}"
        - name: NCCL_P2P_DISABLE
          value: "${NCCL_P2P_DISABLE}"
        - name: NCCL_IB_DISABLE
          value: "${NCCL_IB_DISABLE}"
        - name: NCCL_P2P_LEVEL
          value: "${NCCL_P2P_LEVEL}"
        - name: NCCL_SOCKET_IFNAME
          value: "${NCCL_SOCKET_IFNAME}"
        - name: NCCL_SHM_DISABLE
          value: "${NCCL_SHM_DISABLE}"
        - name: TRANSFORMERS_CACHE
          value: "/data/hf-cache"
        - name: HF_HUB_ENABLE_HF_TRANSFER
          value: "false"
EOF

    # HuggingFace Token, falls vorhanden
    if [[ -n "$hf_token" ]]; then
        cat >> "$output_file" << EOF
        - name: HF_TOKEN
          valueFrom:
            secretKeyRef:
              name: huggingface-token
              key: token
              optional: true
        - name: HUGGING_FACE_HUB_TOKEN
          valueFrom:
            secretKeyRef:
              name: huggingface-token
              key: token
              optional: true
EOF
    fi

    # API Key, falls vorhanden
    if [[ -n "$api_key" ]]; then
        cat >> "$output_file" << EOF
        - name: TGI_API_KEY
          valueFrom:
            secretKeyRef:
              name: tgi-api-key
              key: token
              optional: true
EOF
    fi

    # Container-Ressourcen und Volumes
    cat >> "$output_file" << EOF
        ports:
        - containerPort: 8000
          protocol: TCP
        resources:
          limits:
            memory: "${MEMORY_LIMIT}"
            cpu: "${CPU_LIMIT}"
            nvidia.com/gpu: ${gpu_count}
          requests:
            memory: "4Gi"
            cpu: "2"
        volumeMounts:
        - name: model-cache
          mountPath: /data
        - name: dshm
          mountPath: /dev/shm
      volumes:
      - name: model-cache
        emptyDir:
          sizeLimit: 30Gi
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: ${DSHM_SIZE}
---
apiVersion: v1
kind: Service
metadata:
  name: ${service_name}
  namespace: ${namespace}
  labels:
    app: llm-server
spec:
  ports:
  - name: http
    port: 8000
    protocol: TCP
    targetPort: 8000
  selector:
    app: llm-server
  type: ClusterIP
EOF
}

# Deployment anwenden
function apply_deployment() {
    local manifest="$1"
    local namespace="$2"
    local deployment_name="$3"
    
    info "Wende Deployment an..."
    kubectl apply -f "$manifest"
    
    info "Warte auf erfolgreichen Start des TGI Deployments..."
    if ! kubectl -n "$namespace" rollout status deployment/"$deployment_name" --timeout=300s; then
        error "Deployment fehlgeschlagen. Überprüfen Sie die Logs mit: kubectl -n $namespace logs -l app=llm-server"
    fi
}

# Zusammenfassung anzeigen
function display_summary() {
    local model="$1"
    local namespace="$2"
    local service_name="$3"
    local deployment_name="$4"
    local api_key="$5"
    local gpu_count="$6"
    
    echo
    success "✅ TGI Deployment erfolgreich gestartet"
    echo
    echo "🚀 Verwendetes Modell: $model"
    echo "🌐 Service erreichbar über: $service_name:8000 (intern)"
    echo "🛡️ API-Schlüssel: $([ -n "$api_key" ] && echo "Konfiguriert" || echo "Nicht konfiguriert (ungeschützt)")"
    
    if [ "$gpu_count" -gt 1 ]; then
        echo "🖥️ Multi-GPU Konfiguration: $gpu_count GPUs im Sharded Mode"
    else
        echo "🖥️ Single-GPU Konfiguration"
    fi
    
    echo
    echo "📋 Hinweise:"
    echo "- TGI bietet eine OpenAI-kompatible API"
    echo "- V100-GPU-optimierte Konfiguration"
    echo "- Modelle werden im temporären Speicher abgelegt und bei Pod-Neustart neu geladen"
    echo "- Der Modell-Download kann einige Zeit in Anspruch nehmen"
    echo
    echo "📊 Status überwachen:"
    echo "kubectl -n $namespace logs -f deployment/$deployment_name"
    echo
    echo "🔗 Externer Zugriff (Port-Forwarding):"
    echo "kubectl -n $namespace port-forward svc/$service_name 8000:8000"
}

# ============================================================================
# Hauptprogramm
# ============================================================================

# Banner anzeigen
cat << "EOF"
 _____ ____ ___    ______           __                                  __ 
|_   _/ ___/__ \  /_  __/__  ____  / /___  __  ___   _____  ____  _____/ /_
  | || |    / _/   / / / _ \/ __ \/ / __ \/ / / / | / / _ \/ __ \/ ___/ __/
  | || |___ /_/   / / /  __/ /_/ / / /_/ / /_/ /| |/ /  __/ / / / /  / /_  
  |_| \____/___/  /_/  \___/ .___/_/\____/\__, / |___/\___/_/ /_/_/   \__/  
                         /_/            /____/                       V100
EOF

# Verzeichnisse und Konfiguration einrichten
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$ROOT_DIR/configs/config.sh"

# Konfiguration laden
load_config "$CONFIG_FILE"

# Parameter prüfen
check_model_access "$MODEL_NAME" "$HUGGINGFACE_TOKEN"

# CUDA Devices vorbereiten
CUDA_DEVICES=$(prepare_cuda_devices "$GPU_COUNT")

# Bestehende Ressourcen entfernen
cleanup_resources "$NAMESPACE" "$TGI_DEPLOYMENT_NAME" "$TGI_SERVICE_NAME"

# Secrets erstellen
create_huggingface_secret "$NAMESPACE" "$HUGGINGFACE_TOKEN"
create_api_key_secret "$NAMESPACE" "$TGI_API_KEY"

# Deployment-Konfiguration
info "Deployment-Informationen:"
info "------------------------"
info "Namespace: $NAMESPACE"
info "GPU-Typ: $GPU_TYPE mit $GPU_COUNT GPU(s)"
info "Modell: $MODEL_NAME"
info "Quantisierung: ${QUANTIZATION:-'Keine (float16)'}"
info "CUDA Memory Fraction: $CUDA_MEMORY_FRACTION"
info "Speicherlimits: Input $MAX_INPUT_LENGTH, Total $MAX_TOTAL_TOKENS Tokens"
info "NCCL Konfiguration: DEBUG=$NCCL_DEBUG, P2P=$NCCL_P2P_DISABLE, IB=$NCCL_IB_DISABLE"
info "Shared Memory (dshm): $DSHM_SIZE"
info "------------------------"

# Manifest generieren
TMP_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE"' EXIT

generate_tgi_manifest \
    "$NAMESPACE" \
    "$TGI_DEPLOYMENT_NAME" \
    "$TGI_SERVICE_NAME" \
    "$MODEL_NAME" \
    "$CUDA_DEVICES" \
    "$QUANTIZATION" \
    "$GPU_COUNT" \
    "$GPU_TYPE" \
    "$HUGGINGFACE_TOKEN" \
    "$TGI_API_KEY" \
    "$TMP_FILE"

# Deployment anwenden
apply_deployment "$TMP_FILE" "$NAMESPACE" "$TGI_DEPLOYMENT_NAME"

# Erfolgsinformationen anzeigen
display_summary "$MODEL_NAME" "$NAMESPACE" "$TGI_SERVICE_NAME" "$TGI_DEPLOYMENT_NAME" "$TGI_API_KEY" "$GPU_COUNT"

exit 0
