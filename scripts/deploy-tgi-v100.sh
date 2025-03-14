#!/bin/bash

# Skript zum Deployment von Text Generation Inference (TGI) speziell optimiert für V100 GPUs
# TGI bietet eine OpenAI-kompatible API für die Ausführung von LLMs
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Lade Konfiguration
if [ -f "$ROOT_DIR/configs/config.sh" ]; then
    source "$ROOT_DIR/configs/config.sh"
else
    echo "Fehler: config.sh nicht gefunden."
    exit 1
fi

# Standard-Testmodell - frei verfügbares Modell für Fallback
FREE_MODEL="TinyLlama/TinyLlama-1.1B-Chat-v1.0"

# Verwende das konfigurierte Modell
MODEL_TO_USE="${MODEL_NAME:-$FREE_MODEL}"

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

# Erstelle temporäre Datei
TMP_FILE=$(mktemp)

# Logge den HuggingFace-Token-Status (redacted für Sicherheit)
if [ -n "$HUGGINGFACE_TOKEN" ]; then
    echo "HuggingFace-Token ist konfiguriert (${HUGGINGFACE_TOKEN:0:3}...${HUGGINGFACE_TOKEN: -3})"
else
    echo "WARNUNG: Kein HuggingFace-Token konfiguriert. Gated Modelle werden nicht funktionieren."
fi

# Schreibe YAML für TGI Deployment
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
  selector:
    matchLabels:
      app: llm-server
  template:
    metadata:
      labels:
        app: llm-server
    spec:
EOF

# GPU Tolerationen hinzufügen wenn GPU aktiviert
if [ "$USE_GPU" == "true" ]; then
    cat >> "$TMP_FILE" << EOF
      tolerations:
      - key: "${GPU_TYPE}"
        operator: "Exists"
        effect: "NoSchedule"
EOF
fi

# Container-Definition mit expliziten einzelnen Argumenten
cat >> "$TMP_FILE" << EOF
      containers:
      - name: tgi
        image: ghcr.io/huggingface/text-generation-inference:1.2.0
        imagePullPolicy: IfNotPresent
        command: 
        - "text-generation-launcher"
        args:
        - "--model-id=${MODEL_TO_USE}"
        - "--port=8000"
        - "--dtype=float16"
EOF

# Multi-GPU Parameter - EXPLIZIT separater Eintrag
if [ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -gt 1 ]; then
    cat >> "$TMP_FILE" << EOF
        - "--sharded=true"
EOF
fi

# V100-spezifische Memory-Optimierungen
MAX_INPUT_LENGTH=${MAX_INPUT_LENGTH:-2048}
MAX_TOTAL_TOKENS=${MAX_TOTAL_TOKENS:-4096}
MAX_BATCH_PREFILL_TOKENS=${MAX_BATCH_PREFILL_TOKENS:-4096}
CUDA_MEMORY_FRACTION=${CUDA_MEMORY_FRACTION:-0.85}

cat >> "$TMP_FILE" << EOF
        - "--max-input-length=${MAX_INPUT_LENGTH}"
        - "--max-total-tokens=${MAX_TOTAL_TOKENS}"
        - "--max-batch-prefill-tokens=${MAX_BATCH_PREFILL_TOKENS}"
        - "--cuda-memory-fraction=${CUDA_MEMORY_FRACTION}"
EOF

# Konkurrente Anfragen begrenzen
cat >> "$TMP_FILE" << EOF
        - "--max-concurrent-requests=8"
EOF

# Quantisierungsoptionen
if [ -n "$QUANTIZATION" ]; then
    if [ "$QUANTIZATION" == "awq" ]; then
        cat >> "$TMP_FILE" << EOF
        - "--quantize=awq"
EOF
    elif [ "$QUANTIZATION" == "gptq" ]; then
        cat >> "$TMP_FILE" << EOF
        - "--quantize=gptq"
EOF
    fi
fi

# Umgebungsvariablen
cat >> "$TMP_FILE" << EOF
        env:
EOF

# GPU-spezifische Umgebungsvariablen für V100
if [ "$USE_GPU" == "true" ]; then
    cat >> "$TMP_FILE" << EOF
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
EOF
fi

# HuggingFace Token wenn vorhanden
if [ -n "$HUGGINGFACE_TOKEN" ]; then
    cat >> "$TMP_FILE" << EOF
        - name: HF_TOKEN
          value: "${HUGGINGFACE_TOKEN}"
        - name: HUGGING_FACE_HUB_TOKEN
          value: "${HUGGINGFACE_TOKEN}"
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
EOF

# GPU-Ressourcen
if [ "$USE_GPU" == "true" ]; then
    cat >> "$TMP_FILE" << EOF
            nvidia.com/gpu: ${GPU_COUNT}
EOF
fi

# Speicherressourcen anpassen für V100
cat >> "$TMP_FILE" << EOF
          requests:
            memory: "8Gi"
            cpu: "2"
EOF

# Rest des YAML
cat >> "$TMP_FILE" << EOF
        volumeMounts:
        - name: model-cache
          mountPath: /data
        - name: dshm
          mountPath: /dev/shm
      volumes:
      - name: model-cache
        emptyDir: {}
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: ${DSHM_SIZE:-8Gi}
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
    port: 3333
    protocol: TCP
    targetPort: 8000
  selector:
    app: llm-server
  type: ClusterIP
EOF

# Anwenden der Konfiguration
echo "Deploying Text Generation Inference zu Namespace $NAMESPACE..."
echo "Verwendetes Modell: $MODEL_TO_USE"
echo "Verwendete GPU-Konfiguration: $GPU_TYPE mit $GPU_COUNT GPUs"
echo "Speicher Konfiguration: MAX_INPUT_LENGTH=${MAX_INPUT_LENGTH}, MAX_TOTAL_TOKENS=${MAX_TOTAL_TOKENS}"
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
echo "Service erreichbar über: $TGI_SERVICE_NAME:3333"
echo
echo "HINWEIS: Verwendetes Modell: $MODEL_TO_USE"
echo "HINWEIS: TGI bietet eine OpenAI-kompatible API."
echo "HINWEIS: TGI Port 8000 wird auf Service-Port 3333 gemappt."
echo "HINWEIS: Speziell für V100 GPUs mit ${GPU_COUNT} GPU(s) optimiert"
echo "HINWEIS: TGI muss das Modell jetzt herunterladen, was einige Zeit dauern kann."
echo "Überwachen Sie den Fortschritt mit: kubectl -n $NAMESPACE logs -f deployment/$TGI_DEPLOYMENT_NAME"
echo
echo "Für den Zugriff auf den Service führen Sie aus:"
echo "kubectl -n $NAMESPACE port-forward svc/$TGI_SERVICE_NAME 3333:3333"