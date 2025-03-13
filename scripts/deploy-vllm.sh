#!/bin/bash

# Skript zum Deployment von vLLM mit GPU-Unterstützung ohne ZMQ
# Fügt einen CUDA-Test vor dem Modellstart hinzu
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
    
    # GPU-Umgebungsvariablen für optimale Performance
    CUDA_DEVICES="0"
    if [ "$GPU_COUNT" -gt 1 ]; then
        # Für Multi-GPU: CUDA_VISIBLE_DEVICES mit entsprechender Anzahl
        for ((i=1; i<GPU_COUNT; i++)); do
            CUDA_DEVICES="$CUDA_DEVICES,$i"
        done
    fi
    
    GPU_ENV="
            - name: PATH
              value: /usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
            - name: LD_LIBRARY_PATH
              value: /usr/local/nvidia/lib:/usr/local/nvidia/lib64
            - name: NVIDIA_DRIVER_CAPABILITIES
              value: compute,utility
            - name: CUDA_VISIBLE_DEVICES
              value: \"${CUDA_DEVICES}\"
            - name: VLLM_LOGGING_LEVEL
              value: \"INFO\"
            - name: NCCL_SOCKET_IFNAME
              value: \"eth0\"
            - name: NCCL_DEBUG
              value: \"INFO\""
else
    GPU_TOLERATIONS=""
    GPU_RESOURCES=""
    GPU_ENV=""
fi

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

# CUDA-Test-Skript
CUDA_TEST_SCRIPT="
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
"

# Erstelle YAML für vLLM Deployment mit eigenem Entrypoint und CUDA-Test
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
      initContainers:
        - name: cuda-test
          image: vllm/vllm-openai:latest
          command: ["python", "-c"]
          args:
            - |
              $CUDA_TEST_SCRIPT
          env:$GPU_ENV
          resources:
            limits:
              memory: "2Gi"
              cpu: "1"$GPU_RESOURCES
      containers:
        - image: vllm/vllm-openai:v0.2.5
          name: vllm
          command: ["/bin/bash", "-c"]
          args:
            - >
              python -m vllm.entrypoints.openai.api_server
              --model $MODEL_NAME
              --host 0.0.0.0
              --port 3333
              --gpu-memory-utilization $GPU_MEMORY_UTILIZATION
              --max-model-len $MAX_MODEL_LEN
              --dtype half
              $([ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -gt 1 ] && echo "--tensor-parallel-size $GPU_COUNT")
              $([ -n "$QUANTIZATION" ] && echo "--quantization $QUANTIZATION")
              $([ "$USE_GPU" == "true" ] && [ "$GPU_COUNT" -eq 1 ] && echo "--disable-custom-all-reduce")
          env:
$GPU_ENV$VLLM_API_ENV$HF_TOKEN_ENV
          ports:
            - containerPort: 3333
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
      port: 3333
      protocol: TCP
      targetPort: 3333
  selector:
    service: vllm
  type: ClusterIP
EOF

# Anwenden der Konfiguration
echo "Deploying vLLM to namespace $NAMESPACE mit vLLM v0.2.5 und CUDA-Test..."
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
echo "HINWEIS: vLLM v0.2.5 wird verwendet, die keine ZMQ-Abhängigkeit hat."
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
