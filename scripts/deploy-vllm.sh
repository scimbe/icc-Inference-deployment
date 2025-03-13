#!/bin/bash

# Skript zum Deployment von vLLM mit GPU-Unterstützung ohne ZMQ
# Verwendet Port 3333 statt 8000
# Aktiviert Mixed Precision (half) für optimierten Speicherverbrauch
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

# Variablen für Multiline-Strings
CUDA_TEST_SCRIPT=$(cat << 'EOF'
import torch
import sys
import os

print('=== CUDA Verfügbarkeitstest ===')
print(f'PyTorch Version: {torch.__version__}')
print(f'CUDA verfügbar: {torch.cuda.is_available()}')

if torch.cuda.is_available():
    print(f'CUDA Version: {torch.version.cuda}')
    print(f'Anzahl GPUs: {torch.cuda.device_count()}')
    for i in range(torch.cuda.device_count()):
        print(f'GPU {i}: {torch.cuda.get_device_name(i)}')
    
    # Test der GPU-Speicherzuweisung
    try:
        # 10 MB Tensor auf GPU erstellen
        tensor = torch.rand(10 * 1024 * 1024 // 4, device='cuda')
        print(f'Konnte erfolgreich Tensor mit {tensor.numel() * 4 / 1024 / 1024:.2f} MB auf GPU allozieren')
        del tensor
    except Exception as e:
        print(f'Fehler bei GPU-Speicherallokation: {e}')
else:
    print('WARNUNG: CUDA ist nicht verfügbar!')
    print('Umgebungsvariablen:')
    for k, v in os.environ.items():
        if 'CUDA' in k:
            print(f'{k}: {v}')
    sys.exit(1)

print('CUDA-Test erfolgreich abgeschlossen.')
EOF
)

# CUDA_DEVICES vorbereiten
CUDA_DEVICES="0"
if [ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -gt 1 ]; then
    for ((i=1; i<GPU_COUNT; i++)); do
        CUDA_DEVICES="${CUDA_DEVICES},${i}"
    done
fi

# VLLM Command-Argumente
VLLM_ARGS="python -m vllm.entrypoints.openai.api_server --model ${MODEL_NAME} --host 0.0.0.0 --port 3333 --gpu-memory-utilization ${GPU_MEMORY_UTILIZATION} --max-model-len ${MAX_MODEL_LEN} --dtype half"

if [ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -gt 1 ]; then
    VLLM_ARGS="${VLLM_ARGS} --tensor-parallel-size ${GPU_COUNT}"
fi

if [ -n "$QUANTIZATION" ]; then
    VLLM_ARGS="${VLLM_ARGS} --quantization ${QUANTIZATION}"
fi

if [ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -eq 1 ]; then
    VLLM_ARGS="${VLLM_ARGS} --disable-custom-all-reduce"
fi

# Erstelle YAML für vLLM Deployment
cat > "$TMP_FILE" << EOF
---
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

# InitContainer für CUDA-Test
cat >> "$TMP_FILE" << EOF
      initContainers:
      - name: cuda-test
        image: vllm/vllm-openai:latest
        command: ["python", "-c"]
        args:
        - |
${CUDA_TEST_SCRIPT}
        env:
EOF

# GPU-Umgebungsvariablen für initContainer
if [ "$USE_GPU" == "true" ]; then
    cat >> "$TMP_FILE" << EOF
        - name: PATH
          value: /usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        - name: LD_LIBRARY_PATH
          value: /usr/local/nvidia/lib:/usr/local/nvidia/lib64
        - name: NVIDIA_DRIVER_CAPABILITIES
          value: compute,utility
        - name: CUDA_VISIBLE_DEVICES
          value: "${CUDA_DEVICES}"
        - name: VLLM_LOGGING_LEVEL
          value: "INFO"
        - name: NCCL_SOCKET_IFNAME
          value: "eth0"
        - name: NCCL_DEBUG
          value: "INFO"
EOF
fi

# Init-Container Ressourcen
cat >> "$TMP_FILE" << EOF
        resources:
          limits:
            memory: "2Gi"
            cpu: "1"
EOF

# GPU-Ressourcen für initContainer wenn GPU aktiviert
if [ "$USE_GPU" == "true" ]; then
    cat >> "$TMP_FILE" << EOF
            nvidia.com/gpu: ${GPU_COUNT}
EOF
fi

# Hauptcontainer
cat >> "$TMP_FILE" << EOF
      containers:
      - name: vllm
        image: vllm/vllm-openai:latest
        command: ["/bin/bash", "-c"]
        args:
        - >
          ${VLLM_ARGS}
        env:
EOF

# GPU-Umgebungsvariablen für Hauptcontainer
if [ "$USE_GPU" == "true" ]; then
    cat >> "$TMP_FILE" << EOF
        - name: PATH
          value: /usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        - name: LD_LIBRARY_PATH
          value: /usr/local/nvidia/lib:/usr/local/nvidia/lib64
        - name: NVIDIA_DRIVER_CAPABILITIES
          value: compute,utility
        - name: CUDA_VISIBLE_DEVICES
          value: "${CUDA_DEVICES}"
        - name: VLLM_LOGGING_LEVEL
          value: "INFO"
        - name: NCCL_SOCKET_IFNAME
          value: "eth0"
        - name: NCCL_DEBUG
          value: "INFO"
EOF
fi

# API Key für vLLM
if [ -n "$VLLM_API_KEY" ]; then
    cat >> "$TMP_FILE" << EOF
        - name: VLLM_API_KEY
          value: "${VLLM_API_KEY}"
EOF
fi

# HuggingFace Token
if [ -n "$HUGGINGFACE_TOKEN" ]; then
    cat >> "$TMP_FILE" << EOF
        - name: HUGGING_FACE_HUB_TOKEN
          value: "${HUGGINGFACE_TOKEN}"
EOF
fi

# Rest des Hauptcontainers
cat >> "$TMP_FILE" << EOF
        ports:
        - containerPort: 3333
          protocol: TCP
        resources:
          limits:
            memory: "${MEMORY_LIMIT}"
            cpu: "${CPU_LIMIT}"
EOF

# GPU-Ressourcen für Hauptcontainer wenn GPU aktiviert
if [ "$USE_GPU" == "true" ]; then
    cat >> "$TMP_FILE" << EOF
            nvidia.com/gpu: ${GPU_COUNT}
EOF
fi

# Volumes und Volume Mounts
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
    targetPort: 3333
  selector:
    service: vllm
  type: ClusterIP
EOF

# Anwenden der Konfiguration
echo "Deploying vLLM to namespace $NAMESPACE mit CUDA-Test..."
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
echo "HINWEIS: Ein CUDA-Test wurde als Init-Container hinzugefügt."
echo "HINWEIS: vLLM nutzt Port 3333 statt des standardmäßigen Ports 8000."
echo "HINWEIS: CUDA_VISIBLE_DEVICES ist auf '$CUDA_DEVICES' gesetzt."
echo "HINWEIS: Mixed Precision (half) ist aktiviert, um Speicherverbrauch zu reduzieren."
echo "HINWEIS: vLLM muss das Modell jetzt herunterladen und in den GPU-Speicher laden."
echo "Dieser Vorgang kann je nach Modellgröße einige Minuten bis Stunden dauern."
echo "Überwachen Sie den Fortschritt mit: kubectl -n $NAMESPACE logs -f deployment/$VLLM_DEPLOYMENT_NAME"
echo "Überprüfen Sie die CUDA-Testergebnisse mit: kubectl -n $NAMESPACE logs deployment/$VLLM_DEPLOYMENT_NAME -c cuda-test"
echo
echo "Für den Zugriff auf den Service führen Sie aus:"
echo "kubectl -n $NAMESPACE port-forward svc/$VLLM_SERVICE_NAME 3333:3333"
