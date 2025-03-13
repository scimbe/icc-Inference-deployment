#!/bin/bash

# Skript zum Deployment von vLLM mit GPU-Unterstützung
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

# Erstelle temporäre YAML-Datei für das Deployment
TMP_FILE=$(mktemp)

# GPU-Konfiguration vorbereiten
if [ "$USE_GPU" == "true" ]; then
    GPU_TOLERATIONS="
      tolerations:
        - key: \"$GPU_TYPE\"
          operator: \"Exists\"
          effect: \"NoSchedule\""
    
    # Korrekte Syntax für GPU-Ressourcen in der ICC
    GPU_RESOURCES="
              nvidia.com/gpu: $GPU_COUNT"
    
    GPU_ENV="
            - name: PATH
              value: /usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
            - name: LD_LIBRARY_PATH
              value: /usr/local/nvidia/lib:/usr/local/nvidia/lib64
            - name: NVIDIA_DRIVER_CAPABILITIES
              value: compute,utility
            - name: PYTORCH_CUDA_ALLOC_CONF
              value: expandable_segments:True
            - name: NCCL_DEBUG
              value: \"INFO\"
            - name: NCCL_IB_DISABLE
              value: \"1\"
            - name: NCCL_P2P_DISABLE
              value: \"1\""
else
    GPU_TOLERATIONS=""
    GPU_RESOURCES=""
    GPU_ENV=""
fi

# vLLM-Command-Argumente
VLLM_COMMAND="[\"--model\", \"${MODEL_NAME}\""

# Wenn Quantisierung aktiviert ist
if [ -n "$QUANTIZATION" ]; then
    VLLM_COMMAND+=", \"--quantization\", \"${QUANTIZATION}\""
fi

# Tensor Parallel Size (Multi-GPU)
if [ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -gt 1 ]; then
    VLLM_COMMAND+=", \"--tensor-parallel-size\", \"${GPU_COUNT}\""
fi

# Weitere vLLM-Parameter
VLLM_COMMAND+=", \"--host\", \"0.0.0.0\""
VLLM_COMMAND+=", \"--port\", \"8000\""
VLLM_COMMAND+=", \"--gpu-memory-utilization\", \"${GPU_MEMORY_UTILIZATION}\""
VLLM_COMMAND+=", \"--max-model-len\", \"${MAX_MODEL_LEN}\""

if [ -n "$DTYPE" ]; then
    VLLM_COMMAND+=", \"--dtype\", \"${DTYPE}\""
fi

# Deaktiviere Multi-GPU, falls auf 1 reduziert
if [ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -eq 1 ]; then
    VLLM_COMMAND+=", \"--disable-custom-all-reduce\""
fi

VLLM_COMMAND+="]"

# API Key für vLLM
if [ -n "$VLLM_API_KEY" ]; then
    VLLM_API_ENV="
            - name: VLLM_API_KEY
              value: \"${VLLM_API_KEY}\""
else
    VLLM_API_ENV=""
fi

# HuggingFace Token für geschützte Modelle
if [ -n "$HUGGINGFACE_TOKEN" ]; then
    HF_TOKEN_ENV="
            - name: HUGGING_FACE_HUB_TOKEN
              value: \"${HUGGINGFACE_TOKEN}\""
else
    HF_TOKEN_ENV=""
fi

# Erstelle YAML für vLLM Deployment
cat << EOF > "$TMP_FILE"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $VLLM_DEPLOYMENT_NAME
  namespace: $NAMESPACE
  labels:
    service: vllm
spec:
  replicas: 1
  selector:
    matchLabels:
      service: vllm
  template:
    metadata:
      labels:
        service: vllm
    spec:$GPU_TOLERATIONS
      containers:
        - image: vllm/vllm-openai:latest
          name: vllm
          args: $VLLM_COMMAND
          env:$GPU_ENV$VLLM_API_ENV$HF_TOKEN_ENV
          ports:
            - containerPort: 8000
              protocol: TCP
          resources:
            limits:
              memory: "$MEMORY_LIMIT"
              cpu: "$CPU_LIMIT"$GPU_RESOURCES
          volumeMounts:
            - name: model-cache
              mountPath: /root/.cache/huggingface
            - name: dshm
              mountPath: /dev/shm
      volumes:
        - name: model-cache
          emptyDir: {}
        - name: dshm
          emptyDir:
            medium: Memory
            sizeLimit: 8Gi
---
apiVersion: v1
kind: Service
metadata:
  name: $VLLM_SERVICE_NAME
  namespace: $NAMESPACE
  labels:
    service: vllm
spec:
  ports:
    - name: http
      port: 8000
      protocol: TCP
      targetPort: 8000
  selector:
    service: vllm
  type: ClusterIP
EOF

# Anwenden der Konfiguration
echo "Deploying vLLM to namespace $NAMESPACE..."
echo "Verwendete Konfiguration:"
cat "$TMP_FILE"
echo "---------------------------------"

kubectl apply -f "$TMP_FILE"

# Aufräumen
rm "$TMP_FILE"

# Warte auf das Deployment
echo "Warte auf das vLLM Deployment..."
kubectl -n "$NAMESPACE" rollout status deployment/"$VLLM_DEPLOYMENT_NAME" --timeout=300s

echo "vLLM Deployment gestartet."
echo "Service erreichbar über: $VLLM_SERVICE_NAME:8000"
echo
echo "HINWEIS: vLLM muss das Modell jetzt herunterladen und in den GPU-Speicher laden."
echo "Dieser Vorgang kann je nach Modellgröße einige Minuten bis Stunden dauern."
echo "Überwachen Sie den Fortschritt mit: kubectl -n $NAMESPACE logs -f deployment/$VLLM_DEPLOYMENT_NAME"
