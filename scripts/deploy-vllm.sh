#!/bin/bash

# Skript zum Deployment von vLLM mit GPU-Unterstützung
# Vereinfachte Version zur Vermeidung von YAML-Syntaxproblemen
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

# Schreibe extrem vereinfachte YAML-Datei
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
      containers:
      - name: vllm
        image: vllm/vllm-openai:latest
        ports:
        - containerPort: 3333
          protocol: TCP
        resources:
          limits:
            memory: "${MEMORY_LIMIT}"
            cpu: "${CPU_LIMIT}"
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
echo "Deploying vLLM in minimaler Konfiguration zu namespace $NAMESPACE..."
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
echo "HINWEIS: Diese Version verwendet die Standard-Entrypoints des vLLM-Images."
echo "HINWEIS: vLLM Port 8000 wird auf Service-Port 3333 gemappt."
echo "HINWEIS: vLLM muss das Modell jetzt herunterladen und in den GPU-Speicher laden."
echo "Dieser Vorgang kann je nach Modellgröße einige Minuten bis Stunden dauern."
echo "Überwachen Sie den Fortschritt mit: kubectl -n $NAMESPACE logs -f deployment/$VLLM_DEPLOYMENT_NAME"
echo
echo "Für den Zugriff auf den Service führen Sie aus:"
echo "kubectl -n $NAMESPACE port-forward svc/$VLLM_SERVICE_NAME 3333:3333"
