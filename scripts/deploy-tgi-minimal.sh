#!/bin/bash

# Skript zum Deployment von TGI mit minimalem Setup für Troubleshooting
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
            - name: CUDA_VISIBLE_DEVICES
              value: \"0\""

# Verwende ein kleineres, bekannt funktionierendes Modell für Tests
TEST_MODEL="TinyLlama/TinyLlama-1.1B-Chat-v1.0"

# Minimale Argumente für TGI
TGI_COMMAND="[\"text-generation-launcher\", \"--model-id\", \"${TEST_MODEL}\", \"--port\", \"8000\"]"

# HuggingFace Token falls benötigt
if [ -n "$HUGGINGFACE_TOKEN" ]; then
    HF_TOKEN_ENV="
            - name: HF_TOKEN
              value: \"${HUGGINGFACE_TOKEN}\"
            - name: HUGGING_FACE_HUB_TOKEN
              value: \"${HUGGINGFACE_TOKEN}\""
else
    HF_TOKEN_ENV=""
fi

# Erstelle YAML für TGI Deployment mit minimalster Konfiguration
cat << EOF > "$TMP_FILE"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${TGI_DEPLOYMENT_NAME}-test
  namespace: $NAMESPACE
  labels:
    app: llm-server-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llm-server-test
  template:
    metadata:
      labels:
        app: llm-server-test
    spec:
      tolerations:
        - key: "gpu-tesla-v100"
          operator: "Exists"
          effect: "NoSchedule"
      containers:
        - image: ghcr.io/huggingface/text-generation-inference:1.2.0
          name: tgi
          command: ["text-generation-launcher"]
          args:
          - "--model-id=${TEST_MODEL}"
          - "--port=8000"
          - "--dtype=float16"
          env:$GPU_ENV$HF_TOKEN_ENV
          ports:
            - containerPort: 8000
              protocol: TCP
          resources:
            limits:
              memory: "8Gi"
              cpu: "2"$GPU_RESOURCES
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
  name: ${TGI_SERVICE_NAME}-test
  namespace: $NAMESPACE
  labels:
    app: llm-server-test
spec:
  ports:
    - name: http
      port: 8000
      protocol: TCP
      targetPort: 8000
  selector:
    app: llm-server-test
  type: ClusterIP
EOF

# Anwenden der Konfiguration
echo "Deploying vereinfachtes TGI zu Testzwecken..."
echo "Verwendete Konfiguration:"
cat "$TMP_FILE"
echo "---------------------------------"

kubectl apply -f "$TMP_FILE"

# Aufräumen
rm "$TMP_FILE"

# Warte auf das Deployment
echo "Warte auf das TGI Test-Deployment..."
kubectl -n "$NAMESPACE" rollout status deployment/"${TGI_DEPLOYMENT_NAME}-test" --timeout=300s

echo "TGI Test-Deployment gestartet."
echo "Holen Sie die Logs mit: kubectl -n $NAMESPACE logs -f deployment/${TGI_DEPLOYMENT_NAME}-test"
echo "HINWEIS: Dieses Setup verwendet ein minimales TinyLlama-1.1B-Modell für Testzwecke."
