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

# V100-spezifische Parameter setzen mit Standardwerten falls nicht gesetzt
MAX_INPUT_LENGTH=${MAX_INPUT_LENGTH:-2048}
MAX_TOTAL_TOKENS=${MAX_TOTAL_TOKENS:-4096}
MAX_BATCH_PREFILL_TOKENS=${MAX_BATCH_PREFILL_TOKENS:-4096}
CUDA_MEMORY_FRACTION=${CUDA_MEMORY_FRACTION:-0.85}
DSHM_SIZE=${DSHM_SIZE:-8Gi}
MEMORY_LIMIT=${MEMORY_LIMIT:-16Gi}
CPU_LIMIT=${CPU_LIMIT:-4}

# HuggingFace Token Base64-codieren wenn vorhanden
if [ -n "$HUGGINGFACE_TOKEN" ]; then
    HUGGINGFACE_TOKEN_BASE64=$(echo -n "$HUGGINGFACE_TOKEN" | base64)
    echo "HuggingFace-Token wird verwendet (Base64-codiert)"
else
    HUGGINGFACE_TOKEN_BASE64=""
    echo "WARNUNG: Kein HuggingFace-Token konfiguriert. Gated Modelle werden nicht funktionieren."
fi

# Multi-GPU Konfiguration
SHARDED_ARG=""
if [ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -gt 1 ]; then
    SHARDED_ARG="- \"--sharded=true\""
fi

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
        - "--max-concurrent-requests=8"
EOF

# Sharded-Modus für Multi-GPU
if [ -n "$SHARDED_ARG" ]; then
    echo "$SHARDED_ARG" >> "$TMP_FILE"
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
        persistentVolumeClaim:
          claimName: model-cache-pvc
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

# Erstelle PVC für persistenten Modell-Cache, wenn noch nicht vorhanden
if ! kubectl -n "$NAMESPACE" get pvc "model-cache-pvc" &> /dev/null; then
    cat >> "$TMP_FILE" << EOF
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-cache-pvc
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
EOF
fi

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
echo "Speicher Konfiguration: MAX_INPUT_LENGTH=${MAX_INPUT_LENGTH}, MAX_TOTAL_TOKENS=${MAX_TOTAL_TOKENS}"
echo "Persistenter Speicher: model-cache-pvc (20Gi)"
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
echo "HINWEIS: Modelle werden persistent gespeichert in PVC model-cache-pvc"
echo "HINWEIS: TGI muss das Modell jetzt herunterladen, was einige Zeit dauern kann."
echo "Überwachen Sie den Fortschritt mit: kubectl -n $NAMESPACE logs -f deployment/$TGI_DEPLOYMENT_NAME"
echo
echo "Für den Zugriff auf den Service führen Sie aus:"
echo "kubectl -n $NAMESPACE port-forward svc/$TGI_SERVICE_NAME 8000:8000"
