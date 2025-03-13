#!/bin/bash

# Skript zum Deployment von vLLM mit GPU-Unterstützung
# Mit expliziter Device-Definition
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

# CUDA_DEVICES vorbereiten
CUDA_DEVICES="0"
if [ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -gt 1 ]; then
    for ((i=1; i<GPU_COUNT; i++)); do
        CUDA_DEVICES="${CUDA_DEVICES},${i}"
    done
fi

# Erstelle temporäre Datei
TMP_FILE=$(mktemp)

# Schreibe YAML-Datei mit expliziten Umgebungsvariablen für Geräterkennung
cat > "$TMP_FILE" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${VLLM_DEPLOYMENT_NAME}
  namespace: ${NAMESPACE}
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
      - name: vllm
        image: vllm/vllm-openai:latest
        command: ["python", "-m", "vllm.entrypoints.openai.api_server"]
        args:
        - "--model=${MODEL_NAME}"
        - "--device=cuda"
        - "--host=0.0.0.0"
        - "--port=8000"
        - "--dtype=half"
        - "--gpu-memory-utilization=${GPU_MEMORY_UTILIZATION}"
        - "--max-model-len=${MAX_MODEL_LEN}"
EOF

# Multi-GPU Unterstützung
if [ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -gt 1 ]; then
    cat >> "$TMP_FILE" << EOF
        - "--tensor-parallel-size=${GPU_COUNT}"
EOF
fi

# Quantisierung
if [ -n "$QUANTIZATION" ]; then
    cat >> "$TMP_FILE" << EOF
        - "--quantization=${QUANTIZATION}"
EOF
fi

# Single-GPU Optimierung
if [ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -eq 1 ]; then
    cat >> "$TMP_FILE" << EOF
        - "--disable-custom-all-reduce"
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
        - name: NVIDIA_VISIBLE_DEVICES
          value: "${CUDA_DEVICES}"
EOF
fi

# HuggingFace Token wenn vorhanden
if [ -n "$HUGGINGFACE_TOKEN" ]; then
    cat >> "$TMP_FILE" << EOF
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

# Rest des YAML
cat >> "$TMP_FILE" << EOF
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
  name: ${VLLM_SERVICE_NAME}
  namespace: ${NAMESPACE}
  labels:
    service: vllm
spec:
  ports:
  - name: http
    port: 3333
    protocol: TCP
    targetPort: 8000
  selector:
    service: vllm
  type: ClusterIP
EOF

# Anwenden der Konfiguration
echo "Deploying vLLM zu Namespace $NAMESPACE mit expliziter GPU-Konfiguration..."
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
echo "Service erreichbar über: $VLLM_SERVICE_NAME:3333"
echo
echo "HINWEIS: Diese Version verwendet explizite CUDA-Konfiguration."
echo "HINWEIS: vLLM Port 8000 wird auf Service-Port 3333 gemappt."
echo "HINWEIS: CUDA_VISIBLE_DEVICES ist auf '$CUDA_DEVICES' gesetzt."
echo "HINWEIS: Mixed Precision (half) ist aktiviert, um Speicherverbrauch zu reduzieren."
echo "HINWEIS: vLLM muss das Modell jetzt herunterladen und in den GPU-Speicher laden."
echo "Dieser Vorgang kann je nach Modellgröße einige Minuten bis Stunden dauern."
echo "Überwachen Sie den Fortschritt mit: kubectl -n $NAMESPACE logs -f deployment/$VLLM_DEPLOYMENT_NAME"
echo
echo "Für den Zugriff auf den Service führen Sie aus:"
echo "kubectl -n $NAMESPACE port-forward svc/$VLLM_SERVICE_NAME 3333:3333"
