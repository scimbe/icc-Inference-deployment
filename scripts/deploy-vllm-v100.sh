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

# Farbcodes für Terminal-Ausgaben (ANSI-kompatibel für macOS und Linux)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fehlerbehandlung
function error() {
    echo -e "${RED}FEHLER: $1${NC}" >&2
    exit 1
}

# Info-Ausgabe
function info() {
    echo -e "${BLUE}$1${NC}"
}

# Erfolgs-Ausgabe
function success() {
    echo -e "${GREEN}$1${NC}"
}

# Warnung-Ausgabe
function warn() {
    echo -e "${YELLOW}$1${NC}"
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
    MAX_TOTAL_TOKENS="${MAX_TOTAL_TOKENS:-4096}"
    DSHM_SIZE="${DSHM_SIZE:-8Gi}"
    MEMORY_LIMIT="${MEMORY_LIMIT:-16Gi}"
    CPU_LIMIT="${CPU_LIMIT:-4}"
    TENSOR_PARALLEL_SIZE="${TENSOR_PARALLEL_SIZE:-1}"

    # Standard NCCL-Umgebungsvariablen, falls nicht definiert
    NCCL_DEBUG="${NCCL_DEBUG:-INFO}"
    NCCL_DEBUG_SUBSYS="${NCCL_DEBUG_SUBSYS:-ALL}"
    NCCL_P2P_DISABLE="${NCCL_P2P_DISABLE:-0}"
    NCCL_IB_DISABLE="${NCCL_IB_DISABLE:-0}"
    NCCL_P2P_LEVEL="${NCCL_P2P_LEVEL:-NVL}"
    NCCL_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME:-^lo,docker}"
    NCCL_SHM_DISABLE="${NCCL_SHM_DISABLE:-0}"
    
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

# Manifest generieren
function generate_vllm_manifest() {
    local namespace="$1"
    local deployment_name="$2"
    local service_name="$3"
    local cuda_devices="$4"
    local gpu_count="$5"
    local gpu_type="$6"
    local model="$7"
    local quantization="$8"
    local tensor_parallel_size="$9"
    local output_file="${10}"
    local hf_token="${11}"
    
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
        args:
        - "--model"
        - "${model}"
        - "--host"
        - "0.0.0.0"
        - "--port"
        - "8000"
EOF

    # Füge Tensor Parallel Size hinzu für Multi-GPU
    if [[ "$USE_GPU" == "true" ]] && [[ "$tensor_parallel_size" -gt 1 ]]; then
        cat >> "$output_file" << EOF
        - "--tensor-parallel-size"
        - "${tensor_parallel_size}"
EOF
    fi

    # Füge Quantisierung hinzu (falls konfiguriert)
    if [[ -n "$quantization" ]]; then
        cat >> "$output_file" << EOF
        - "--quantization"
        - "${quantization}"
EOF
    fi

    # Memory-Optimierung
    cat >> "$output_file" << EOF
        - "--max-model-len"
        - "${MAX_TOTAL_TOKENS}"
        - "--block-size"
        - "${BLOCK_SIZE}"
        - "--swap-space"
        - "${SWAP_SPACE}"
        - "--dtype"
        - "float16"
        - "--enforce-eager"
EOF

    # max-num-seqs verwenden statt max-batch-size (neueres vLLM API)
    if [ -n "${MAX_CONCURRENT_REQUESTS}" ]; then
        cat >> "$output_file" << EOF
        - "--max-num-seqs"
        - "${MAX_CONCURRENT_REQUESTS}"
EOF
    elif [ -n "${MAX_BATCH_SIZE}" ]; then
        warn "WARNUNG: Parameter MAX_BATCH_SIZE wird umbenannt in MAX_NUM_SEQS für Kompatibilität mit neuerer vLLM-Version"
        cat >> "$output_file" << EOF
        - "--max-num-seqs"
        - "${MAX_BATCH_SIZE}"
EOF
    fi

    # Container Environment fortsetzen
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

# GPU-Konfiguration ausgeben
if [[ "$USE_GPU" == "true" ]] && [[ "$GPU_COUNT" -gt 1 ]]; then
    info "Multi-GPU Konfiguration: $GPU_COUNT GPUs"
else
    info "Single-GPU Konfiguration"
fi

# CUDA Devices vorbereiten
CUDA_DEVICES="0"
if [[ "$USE_GPU" == "true" ]] && [[ "$GPU_COUNT" -gt 1 ]]; then
    for ((i=1; i<GPU_COUNT; i++)); do
        CUDA_DEVICES="${CUDA_DEVICES},$i"
    done
fi

# Bestehende Ressourcen entfernen
cleanup_resources "$NAMESPACE" "$VLLM_DEPLOYMENT_NAME" "$VLLM_SERVICE_NAME"

# Secrets erstellen
create_huggingface_secret "$NAMESPACE" "$HUGGINGFACE_TOKEN"

# Tensor Parallel Size bestimmen
if [ -z "$TENSOR_PARALLEL_SIZE" ] || [ "$TENSOR_PARALLEL_SIZE" -lt 1 ]; then
    TENSOR_PARALLEL_SIZE=1
    info "Tensor Parallel Size auf 1 gesetzt (Keine Parallelisierung)"
fi

# Falls TENSOR_PARALLEL_SIZE größer als GPU_COUNT, entsprechend warnen
if [ "$TENSOR_PARALLEL_SIZE" -gt "$GPU_COUNT" ]; then
    warn "WARNUNG: TENSOR_PARALLEL_SIZE ($TENSOR_PARALLEL_SIZE) größer als GPU_COUNT ($GPU_COUNT)"
    warn "Tensor Parallel Size wird auf GPU_COUNT ($GPU_COUNT) begrenzt"
    TENSOR_PARALLEL_SIZE=$GPU_COUNT
fi

# Deployment-Konfiguration
info "Deployment-Informationen:"
info "------------------------"
info "Namespace: $NAMESPACE"
info "GPU-Typ: $GPU_TYPE mit $GPU_COUNT GPU(s)"
info "Modell: $MODEL_NAME"
info "Quantisierung: ${QUANTIZATION:-'Keine'}"
info "Tensor Parallel Size: $TENSOR_PARALLEL_SIZE"
info "Max Model Length: $MAX_TOTAL_TOKENS"
info "Block Size: $BLOCK_SIZE"
info "Swap Space: $SWAP_SPACE GB"
info "NCCL Konfiguration: DEBUG=$NCCL_DEBUG, P2P=$NCCL_P2P_DISABLE, IB=$NCCL_IB_DISABLE"
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
    "$MODEL_NAME" \
    "$QUANTIZATION" \
    "$TENSOR_PARALLEL_SIZE" \
    "$TMP_FILE" \
    "$HUGGINGFACE_TOKEN"

# Manifest überprüfen (debugging)
echo "DEBUG: Überprüfe YAML-Manifest auf Fehler..."
if command -v yamllint &> /dev/null; then
    yamllint -d relaxed "$TMP_FILE" || (cat "$TMP_FILE" && error "YAML-Validierung fehlgeschlagen")
fi

if command -v kubectl &> /dev/null; then
    kubectl apply --dry-run=server -f "$TMP_FILE" || (cat "$TMP_FILE" && error "Kubernetes Validierung fehlgeschlagen")
fi

# Deployment anwenden
apply_deployment "$TMP_FILE" "$NAMESPACE" "$VLLM_DEPLOYMENT_NAME"

# Erfolgsinformationen anzeigen
display_summary "$MODEL_NAME" "$NAMESPACE" "$VLLM_SERVICE_NAME" "$VLLM_DEPLOYMENT_NAME"

exit 0