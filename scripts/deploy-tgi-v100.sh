#!/bin/bash

# Skript zum Deployment von Text Generation Inference (TGI) speziell optimiert für V100 GPUs
# mit IntelliJ MCP Integration und persistentem Speicher
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Lade Konfiguration
if [ -f "$ROOT_DIR/configs/config.sh" ]; then
    source "$ROOT_DIR/configs/config.sh"
else
    echo "Fehler: config.sh nicht gefunden."
    echo "Bitte kopieren Sie configs/config.example.sh nach configs/config.sh und passen Sie die Werte an."
    exit 1
fi

# Standard-Testmodell - frei verfügbares Modell für Fallback
FREE_MODEL="TinyLlama/TinyLlama-1.1B-Chat-v1.0"

# Verwende das konfigurierte Modell
MODEL_TO_USE="${MODEL_NAME:-$FREE_MODEL}"

# Überprüfung, ob das Modell gated ist und ein HuggingFace-Token existiert
GATED_MODELS=("meta-llama/Llama-2-7b-chat-hf" "meta-llama/Llama-2-13b-chat-hf")
IS_GATED=false
for gated_model in "${GATED_MODELS[@]}"; do
    if [[ "$MODEL_TO_USE" == *"$gated_model"* ]]; then
        IS_GATED=true
        break
    fi
done

if [ "$IS_GATED" = true ] && [ -z "$HUGGINGFACE_TOKEN" ]; then
    echo "FEHLER: Das gewählte Modell '$MODEL_TO_USE' ist ein gated Model und erfordert ein HuggingFace-Token."
    echo "Bitte setzen Sie HUGGINGFACE_TOKEN in config.sh oder wählen Sie ein freies Modell."
    exit 1
fi

# Entferne bestehende Deployments, falls vorhanden
if kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Entferne bestehendes Deployment..."
    kubectl -n "$NAMESPACE" delete deployment "$TGI_DEPLOYMENT_NAME" --ignore-not-found=true
fi

if kubectl -n "$NAMESPACE" get service "$TGI_SERVICE_NAME" &> /dev/null; then
    echo "Entferne bestehenden Service..."
    kubectl -n "$NAMESPACE" delete service "$TGI_SERVICE_NAME" --ignore-not-found=true
fi

# CUDA_DEVICES vorbereiten
CUDA_DEVICES="0"
if [ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -gt 1 ]; then
    for ((i=1; i<GPU_COUNT; i++)); do
        CUDA_DEVICES="${CUDA_DEVICES},$i"
    done
fi

# V100-spezifische Parameter setzen mit Standardwerten falls nicht gesetzt
# Kompatibilität mit beiden Variablennamen (GPU_MEMORY_UTILIZATION und CUDA_MEMORY_FRACTION)
if [ -n "$GPU_MEMORY_UTILIZATION" ]; then
    CUDA_MEMORY_FRACTION="${GPU_MEMORY_UTILIZATION}"
else
    CUDA_MEMORY_FRACTION="${CUDA_MEMORY_FRACTION:-0.9}"
fi

# Andere Parameter mit Standardwerten
MAX_INPUT_LENGTH=${MAX_INPUT_LENGTH:-4096}
MAX_TOTAL_TOKENS=${MAX_TOTAL_TOKENS:-8192}
MAX_BATCH_PREFILL_TOKENS=${MAX_BATCH_PREFILL_TOKENS:-4096}
DSHM_SIZE=${DSHM_SIZE:-8Gi}
MEMORY_LIMIT=${MEMORY_LIMIT:-16Gi}
CPU_LIMIT=${CPU_LIMIT:-4}
PVC_SIZE=${PVC_SIZE:-20Gi}
MAX_CONCURRENT_REQUESTS=$((8 * (GPU_COUNT > 0 ? GPU_COUNT : 1)))
DISABLE_FLASH_ATTENTION=${DISABLE_FLASH_ATTENTION:-false}

# HuggingFace Token Base64-codieren wenn vorhanden
if [ -n "$HUGGINGFACE_TOKEN" ]; then
    HUGGINGFACE_TOKEN_BASE64=$(echo -n "$HUGGINGFACE_TOKEN" | base64)
    echo "HuggingFace-Token wird verwendet (Base64-codiert)"
else
    HUGGINGFACE_TOKEN_BASE64=""
    echo "WARNUNG: Kein HuggingFace-Token konfiguriert. Gated Modelle werden nicht funktionieren."
fi

# API-Key konfigurieren, falls vorhanden
if [ -n "$TGI_API_KEY" ]; then
    TGI_API_KEY_BASE64=$(echo -n "$TGI_API_KEY" | base64)
    echo "TGI API-Key wird konfiguriert"
else
    TGI_API_KEY_BASE64=""
    echo "WARNUNG: Kein TGI API-Key konfiguriert. Die API ist nicht geschützt."
fi

# Multi-GPU Konfiguration
SHARDED_ARG=""
if [ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -gt 1 ]; then
    SHARDED_ARG="        - \"--sharded=true\""
fi

# Erstelle temporäre Datei
TMP_FILE=$(mktemp)

# Schreibe YAML für TGI Deployment mit PVC und Secret
cat > "$TMP_FILE" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${TGI_DEPLOYMENT_NAME}
  namespace: ${NAMESPACE}
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
      - key: "${GPU_TYPE}"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: tgi
        image: ghcr.io/huggingface/text-generation-inference:latest
        imagePullPolicy: IfNotPresent
        command:
        - "text-generation-launcher"
        args:
        - "--model-id=${MODEL_TO_USE}"
        - "--port=8000"
EOF

# Entweder dtype oder quantize setzen, aber nicht beides
if [ -n "$QUANTIZATION" ]; then
    cat >> "$TMP_FILE" << EOF
        - "--quantize=${QUANTIZATION}"
EOF
else
    cat >> "$TMP_FILE" << EOF
        - "--dtype=float16"
EOF
fi

# V100-spezifische Parameter ergänzen
cat >> "$TMP_FILE" << EOF
        - "--max-input-length=${MAX_INPUT_LENGTH}"
        - "--max-total-tokens=${MAX_TOTAL_TOKENS}"
        - "--max-batch-prefill-tokens=${MAX_BATCH_PREFILL_TOKENS}"
        - "--cuda-memory-fraction=${CUDA_MEMORY_FRACTION}"
        - "--max-concurrent-requests=${MAX_CONCURRENT_REQUESTS}"
EOF

# Flash Attention konfigurieren
if [ "$DISABLE_FLASH_ATTENTION" == "true" ]; then
    cat >> "$TMP_FILE" << EOF
        - "--disable-flash-attention=true"
EOF
fi

# Sharded-Modus für Multi-GPU
if [ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -gt 1 ]; then
    cat >> "$TMP_FILE" << EOF
        - "--sharded=true"
EOF
fi

# Umgebungsvariablen
cat >> "$TMP_FILE" << EOF
        env:
        - name: CUDA_VISIBLE_DEVICES
          value: "${CUDA_DEVICES}"
        - name: NCCL_DEBUG
          value: "INFO"
        - name: NCCL_SOCKET_IFNAME
          value: "^lo,docker"
        - name: NCCL_P2P_LEVEL
          value: "NVL"
        - name: TRANSFORMERS_CACHE
          value: "/data/hf-cache"
        - name: HF_HUB_ENABLE_HF_TRANSFER
          value: "false"
EOF

# HuggingFace Token über Secret einbinden wenn vorhanden
if [ -n "$HUGGINGFACE_TOKEN_BASE64" ]; then
    cat >> "$TMP_FILE" << EOF
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

# API Key konfigurieren wenn vorhanden
if [ -n "$TGI_API_KEY_BASE64" ]; then
    cat >> "$TMP_FILE" << EOF
        - name: TGI_API_KEY
          valueFrom:
            secretKeyRef:
              name: tgi-api-key
              key: token
              optional: true
EOF
fi

# Container-Fortsetzung
cat >> "$TMP_FILE" << EOF
        ports:
        - containerPort: 8000
          protocol: TCP
        resources:
          limits:
            memory: "${MEMORY_LIMIT}"
            cpu: "${CPU_LIMIT}"
            nvidia.com/gpu: ${GPU_COUNT}
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
  name: ${TGI_SERVICE_NAME}
  namespace: ${NAMESPACE}
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

# Kein PVC mehr nötig, da emptyDir verwendet wird

# Erstelle Secret für HuggingFace Token, wenn vorhanden
if [ -n "$HUGGINGFACE_TOKEN_BASE64" ]; then
    cat >> "$TMP_FILE" << EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: huggingface-token
  namespace: ${NAMESPACE}
type: Opaque
data:
  token: ${HUGGINGFACE_TOKEN_BASE64}
EOF
fi

# Erstelle Secret für TGI API Key, wenn vorhanden
if [ -n "$TGI_API_KEY_BASE64" ]; then
    cat >> "$TMP_FILE" << EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: tgi-api-key
  namespace: ${NAMESPACE}
type: Opaque
data:
  token: ${TGI_API_KEY_BASE64}
EOF
fi

# Anwenden der Konfiguration
echo "Deploying Text Generation Inference zu Namespace $NAMESPACE..."
echo "Verwendetes Modell: $MODEL_TO_USE"
echo "Verwendete GPU-Konfiguration: $GPU_TYPE mit $GPU_COUNT GPUs"
echo "Rollout-Strategie: Recreate (100% Ressourcennutzung)"
if [ -n "$QUANTIZATION" ]; then
    echo "Quantisierung aktiviert: $QUANTIZATION"
else
    echo "Datentyp gesetzt auf: float16"
fi
echo "Flash Attention: $([ "$DISABLE_FLASH_ATTENTION" == "true" ] && echo "deaktiviert" || echo "aktiviert")"
echo "Speicher Konfiguration: MAX_INPUT_LENGTH=${MAX_INPUT_LENGTH}, MAX_TOTAL_TOKENS=${MAX_TOTAL_TOKENS}"
echo "CUDA Memory Fraction: ${CUDA_MEMORY_FRACTION}"
echo "Flüchtiger Speicher: emptyDir mit 30Gi (auf Festplatte, nicht im RAM)"
echo "Max. concurrent requests: ${MAX_CONCURRENT_REQUESTS}"
echo "Verwendete Konfiguration:"
cat "$TMP_FILE"
echo "---------------------------------"

kubectl apply -f "$TMP_FILE"

# Aufräumen
rm "$TMP_FILE"

# Warte auf das Deployment
echo "Warte auf das TGI Deployment..."
kubectl -n "$NAMESPACE" rollout status deployment/"$TGI_DEPLOYMENT_NAME" --timeout=300s

echo "TGI Deployment gestartet."
echo "Service erreichbar über: $TGI_SERVICE_NAME:8000"
echo
echo "HINWEIS: Verwendetes Modell: $MODEL_TO_USE"
echo "HINWEIS: TGI bietet eine OpenAI-kompatible API."
echo "HINWEIS: TGI Port 8000 wird direkt gemappt."
echo "HINWEIS: Speziell für V100 GPUs mit ${GPU_COUNT} GPU(s) optimiert"
echo "HINWEIS: Modelle werden temporär im emptyDir gespeichert und bei Pod-Neustart neu geladen"
if [ -n "$TGI_API_KEY" ]; then
    echo "HINWEIS: API-Zugriff mit API-Key konfiguriert"
fi
echo "HINWEIS: TGI muss das Modell jetzt herunterladen, was einige Zeit dauern kann."
echo "Überwachen Sie den Fortschritt mit: kubectl -n $NAMESPACE logs -f deployment/$TGI_DEPLOYMENT_NAME"
echo
echo "Für den Zugriff auf den Service führen Sie aus:"
echo "kubectl -n $NAMESPACE port-forward svc/$TGI_SERVICE_NAME 8000:8000"
