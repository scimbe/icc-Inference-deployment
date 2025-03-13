#!/bin/bash

# Skript zum Deployment von Text Generation Inference (TGI) als Alternative zu vLLM
# TGI bietet ebenfalls eine OpenAI-kompatible API und hat eine robustere Geräteerkennung
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

# Standard-Testmodell, falls benötigt
TEST_MODEL="TinyLlama/TinyLlama-1.1B-Chat-v1.0"
MODEL_TO_USE="${MODEL_NAME:-$TEST_MODEL}"

# Entferne bestehende Deployments, falls vorhanden
if kubectl -n "$NAMESPACE" get deployment "$VLLM_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Entferne bestehendes Deployment..."
    kubectl -n "$NAMESPACE" delete deployment "$VLLM_DEPLOYMENT_NAME" --ignore-not-found=true
fi

if kubectl -n "$NAMESPACE" get service "$VLLM_SERVICE_NAME" &> /dev/null; then
    echo "Entferne bestehenden Service..."
    kubectl -n "$NAMESPACE" delete service "$VLLM_SERVICE_NAME" --ignore-not-found=true
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

# Schreibe YAML für TGI Deployment
cat > "$TMP_FILE" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${VLLM_DEPLOYMENT_NAME}
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

# Container-Definition
cat >> "$TMP_FILE" << EOF
      containers:
      - name: tgi
        image: ghcr.io/huggingface/text-generation-inference:1.2.0
        imagePullPolicy: IfNotPresent
        command: ["text-generation-launcher"]
        args:
        - "--model-id=${MODEL_TO_USE}"
        - "--port=8000"
EOF

# Mixed Precision - korrigierte Version
cat >> "$TMP_FILE" << EOF
        - "--dtype=float16"
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

# Multi-GPU Parameter
if [ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -gt 1 ]; then
    cat >> "$TMP_FILE" << EOF
        - "--sharded=true"
EOF
fi

# Umgebungsvariablen
cat >> "$TMP_FILE" << EOF
        env:
EOF

# GPU-spezifische Umgebungsvariablen
if [ "$USE_GPU" == "true" ]; then
    cat >> "$TMP_FILE" << EOF
        - name: CUDA_VISIBLE_DEVICES
          value: "${CUDA_DEVICES}"
EOF
fi

# HuggingFace Token wenn vorhanden
if [ -n "$HUGGINGFACE_TOKEN" ]; then
    cat >> "$TMP_FILE" << EOF
        - name: HF_TOKEN
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
          sizeLimit: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: ${VLLM_SERVICE_NAME}
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
echo "Verwendete Konfiguration:"
cat "$TMP_FILE"
echo "---------------------------------"

kubectl apply -f "$TMP_FILE"

# Aufräumen
rm "$TMP_FILE"

# Warte auf das Deployment
echo "Warte auf das TGI Deployment..."
kubectl -n "$NAMESPACE" rollout status deployment/"$VLLM_DEPLOYMENT_NAME" --timeout=300s

echo "TGI Deployment gestartet."
echo "Service erreichbar über: $VLLM_SERVICE_NAME:3333"
echo
echo "HINWEIS: Text Generation Inference (TGI) wird anstelle von vLLM verwendet."
echo "HINWEIS: TGI bietet auch eine OpenAI-kompatible API."
echo "HINWEIS: TGI Port 8000 wird auf Service-Port 3333 gemappt."
echo "HINWEIS: Mixed Precision (float16) ist aktiviert, um Speicherverbrauch zu reduzieren."
echo "HINWEIS: TGI muss das Modell jetzt herunterladen, was einige Zeit dauern kann."
echo "Überwachen Sie den Fortschritt mit: kubectl -n $NAMESPACE logs -f deployment/$VLLM_DEPLOYMENT_NAME"
echo
echo "Für den Zugriff auf den Service führen Sie aus:"
echo "kubectl -n $NAMESPACE port-forward svc/$VLLM_SERVICE_NAME 3333:3333"
