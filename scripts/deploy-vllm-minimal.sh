#!/bin/bash

# Skript zum Deployment von vLLM mit minimalem Setup für Troubleshooting
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

# GPU-Konfiguration - extrem vereinfacht
GPU_RESOURCES="
              nvidia.com/gpu: 1"

# Minimale Umgebungsvariablen
GPU_ENV="
            - name: NCCL_DEBUG
              value: \"WARN\"
            - name: RAY_memory_monitor_refresh_ms
              value: \"0\""

# Verwende ein kleineres, bekannt funktionierendes Modell für Tests
TEST_MODEL="microsoft/phi-2"

# Sehr einfache Argumente - absolute Minimaleinstellung
VLLM_COMMAND="[\"--model\", \"${TEST_MODEL}\", \"--host\", \"0.0.0.0\", \"--port\", \"8000\"]"

# HuggingFace Token falls benötigt
if [ -n "$HUGGINGFACE_TOKEN" ]; then
    HF_TOKEN_ENV="
            - name: HUGGING_FACE_HUB_TOKEN
              value: \"${HUGGINGFACE_TOKEN}\""
else
    HF_TOKEN_ENV=""
fi

# Erstelle YAML für vLLM Deployment mit minimalster Konfiguration
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
    spec:
      tolerations:
        - key: "gpu-tesla-v100"
          operator: "Exists"
          effect: "NoSchedule"
      containers:
        - image: vllm/vllm-openai:latest
          name: vllm
          args: $VLLM_COMMAND
          env:$GPU_ENV$HF_TOKEN_ENV
          ports:
            - containerPort: 8000
              protocol: TCP
          resources:
            limits:
              memory: "16Gi"
              cpu: "4"$GPU_RESOURCES
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
echo "Deploying vereinfachtes vLLM zu Testzwecken..."
echo "Verwendete Konfiguration:"
cat "$TMP_FILE"
echo "---------------------------------"

kubectl apply -f "$TMP_FILE"

# Aufräumen
rm "$TMP_FILE"

# Warte auf das Deployment
echo "Warte auf das vLLM Deployment..."
kubectl -n "$NAMESPACE" rollout status deployment/"$VLLM_DEPLOYMENT_NAME" --timeout=300s

echo "vLLM Test-Deployment gestartet."
echo "Holen Sie die Logs mit: kubectl -n $NAMESPACE logs -f deployment/$VLLM_DEPLOYMENT_NAME"
echo "HINWEIS: Dieses Setup verwendet ein minimales Phi-2 Modell für Testzwecke."
