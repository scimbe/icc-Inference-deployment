#!/bin/bash
# ============================================================================
# vLLM Deployment Script für V100 GPUs
# ============================================================================
# Autor: HAW Hamburg ICC Team
# Version: 2.0.0
# 
# Dieses Skript erstellt ein optimiertes vLLM Deployment mit V100-spezifischen
# Einstellungen auf der ICC Kubernetes-Plattform.
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
    BLOCK_SIZE="${BLOCK_SIZE:-16}"
    SWAP_SPACE="${SWAP_SPACE:-4}"
    MAX_BATCH_SIZE="${MAX_BATCH_SIZE:-32}"
    MAX_TOTAL_TOKENS="${MAX_TOTAL_TOKENS:-4096}"
    DSHM_SIZE="${DSHM_SIZE:-8Gi}"
    MEMORY_LIMIT="${MEMORY_LIMIT:-16Gi}"
    CPU_LIMIT="${CPU_LIMIT:-4}"
    
    # vLLM-spezifische Namen falls nicht definiert
    VLLM_DEPLOYMENT_NAME="${VLLM_DEPLOYMENT_NAME:-vllm-server}"
    VLLM_SERVICE_NAME="${VLLM_SERVICE_NAME:-vllm-service}"
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

# vLLM Argumente generieren
function generate_vllm_args() {
    local model="$1"
    local gpu_count="$2"
    local quantization="$3"
    
    # Basis-Argumente
    local args="--model ${model} --host 0.0.0.0 --port 8000"
    
    # Quantisierung hinzufügen (falls konfiguriert)
    if [[ -n "$quantization" ]]; then
        args="$args --quantization ${quantization}"
    fi
    
    # Multi-GPU Konfiguration
    if [[ "$USE_GPU" == "true" ]] && [[ "$gpu_count" -gt 1 ]]; then
        args="$args --tensor-parallel-size ${gpu_count}"
    fi
    
    # Memory-Optimierung
    args="$args --max-model-len ${MAX_TOTAL_TOKENS} --block-size ${BLOCK_SIZE} --swap-space ${SWAP_SPACE} --max-batch-size ${MAX_BATCH_SIZE}"
    
    # JSON-formatierte Argumente erstellen
    local json_args="["
    
    # Argumente aufteilen und als JSON-Array formatieren
    IFS=' ' read -ra ARGS_ARRAY <<< "$args"
    for i in "${!ARGS_ARRAY[@]}"; do
        arg="${ARGS_ARRAY[$i]}"
        json_args+="\"$arg\""
        
        # Komma hinzufügen, wenn nicht das letzte Element
        if (( i < ${#ARGS_ARRAY[@]} - 1 )); then
            json_args+=", "
        fi
    done
    
    json_args+="]"
    echo "$json_args"
}

# Manifest generieren
function generate_vllm_manifest() {
    local namespace="$1"
    local deployment_name="$2"
    local service_name="$3"
    local cuda_devices="$4"
    local gpu_count="$5"
    local gpu_type="$6"
    local vllm_args="$7"
    local hf_token="$8"
    local output_file="$9"
    
    # Erstelle Manifest
    cat > "$output_file" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${deployment_name}
  namespace: ${namespace}
  labels:
    service: vllm-server
spec:
  replicas: 1
  selector:
    matchLabels:
      service: vllm-server
  template:
    metadata:
      labels:
        service: vllm-server
    spec:
      tolerations:
      - key: "${gpu_type}"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: vllm
        image: vllm/vllm-openai:latest
        imagePullPolicy: IfNotPresent
        args: ${vllm_args}
        env:
        - name: CUDA_VISIBLE_DEVICES
          value: "${cuda_devices}"
        - name: NCCL_DEBUG
          value: "INFO"
        - name: NCCL_SOCKET_IFNAME
          value: "^lo,docker"
EOF

    # HuggingFace Token, falls vorhanden
    if [[ -n "$hf_token" ]]; then
        cat >> "$output_file" << EOF
        - name: HUGGING_FACE_HUB_TOKEN
          valueFrom:
            secretKeyRef:
              name: huggingface-token
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
          mountPath: /root/.cache/huggingface
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
    service: vllm-server
spec:
  ports:
  - name: http
    port: 8000
    protocol: TCP
    targetPort: 8000
  selector:
    service: vllm-server
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
    
    info "Warte auf erfolgreichen Start des vLLM Deployments..."
    if ! kubectl -n "$namespace" rollout status deployment/"$deployment_name" --timeout=300s; then
        error "Deployment fehlgeschlagen. Überprüfen Sie die Logs mit: kubectl -n $namespace logs -l service=vllm-server"
    fi
}

# Zusammenfassung anzeigen
function display_summary() {
    local model="$1"
    local namespace="$2"
    local service_name="$3"
    local deployment_name="$4"
    
    echo
    success "✅ vLLM Deployment erfolgreich gestartet"
    echo
    echo "🚀 Verwendetes Modell: $model"
    echo "🌐 Service erreichbar über: $service_name:8000 (intern)"
    echo
    echo "📋 Hinweise:"
    echo "- vLLM bietet eine OpenAI-kompatible API"
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
 ___      ___  _      _      __  __    ______           __                                  __ 
|   \    /  _|| |    | |    |  \/  |  /_  __/__  ____  / /___  __  ___   _____  ____  _____/ /_
| |\ \  /  /  | |    | |    | |\/| |   / / / _ \/ __ \/ / __ \/ / / / | / / _ \/ __ \/ ___/ __/
| | \ \/  /   | |___ | |___ | |  | |  / / /  __/ /_/ / / /_/ / /_/ /| |/ /  __/ / / / /  / /_  
|_|  \___/    |_____||_____||_|  |_|  /_/  \___/ .___/_/\____/\__, / |___/\___/_/ /_/_/   \__/  
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
cleanup_resources "$NAMESPACE" "$VLLM_DEPLOYMENT_NAME" "$VLLM_SERVICE_NAME"

# Secrets erstellen
create_huggingface_secret "$NAMESPACE" "$HUGGINGFACE_TOKEN"

# vLLM Argumente generieren
VLLM_ARGS=$(generate_vllm_args "$MODEL_NAME" "$GPU_COUNT" "$QUANTIZATION")

# Deployment-Konfiguration
info "Deployment-Informationen:"
info "------------------------"
info "Namespace: $NAMESPACE"
info "GPU-Typ: $GPU_TYPE mit $GPU_COUNT GPU(s)"
info "Modell: $MODEL_NAME"
info "Quantisierung: ${QUANTIZATION:-'Keine'}"
info "Tensor Parallel Size: $GPU_COUNT"
info "Max Model Length: $MAX_TOTAL_TOKENS"
info "Block Size: $BLOCK_SIZE"
info "Swap Space: $SWAP_SPACE GB"
info "Max Batch Size: $MAX_BATCH_SIZE"
info "------------------------"

# Manifest generieren
TMP_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE"' EXIT

generate_vllm_manifest \
    "$NAMESPACE" \
    "$VLLM_DEPLOYMENT_NAME" \
    "$VLLM_SERVICE_NAME" \
    "$CUDA_DEVICES" \
    "$GPU_COUNT" \
    "$GPU_TYPE" \
    "$VLLM_ARGS" \
    "$HUGGINGFACE_TOKEN" \
    "$TMP_FILE"

# Deployment anwenden
apply_deployment "$TMP_FILE" "$NAMESPACE" "$VLLM_DEPLOYMENT_NAME"

# Erfolgsinformationen anzeigen
display_summary "$MODEL_NAME" "$NAMESPACE" "$VLLM_SERVICE_NAME" "$VLLM_DEPLOYMENT_NAME"

exit 0
