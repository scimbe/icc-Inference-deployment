#!/bin/bash

# Skript zum Testen von TGI mit V100 GPUs
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

# Setze Farben für bessere Lesbarkeit
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== V100 GPU Kompatibilitätstest für TGI ===${NC}"
echo -e "Überprüfe GPU-Typ und Konfiguration..."

# Prüfe, ob der GPU-Typ V100 ist
if [[ "$GPU_TYPE" != *"v100"* ]]; then
    echo -e "${YELLOW}Warnung: Der konfigurierte GPU-Typ ist nicht V100 (aktuell: $GPU_TYPE).${NC}"
    echo -e "Dieses Skript ist speziell für Tesla V100 GPUs optimiert."
    read -p "Möchten Sie trotzdem fortfahren? (j/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        echo "Abbruch"
        exit 1
    fi
fi

echo -e "${BLUE}1. Überprüfe verfügbare GPU-Ressourcen${NC}"
AVAILABLE_GPUS=$(kubectl get nodes -o=custom-columns=NODE:.metadata.name,GPU:.status.capacity.'nvidia\.com/gpu' | grep -v "<none>")
if [ -z "$AVAILABLE_GPUS" ]; then
    echo -e "${RED}Keine GPUs im Cluster gefunden. Überprüfen Sie die Knotenverfügbarkeit.${NC}"
    exit 1
else
    echo -e "${GREEN}Verfügbare GPU-Knoten:${NC}"
    echo "$AVAILABLE_GPUS"
fi

echo -e "\n${BLUE}2. Erstelle ein minimales TGI-Deployment für Tests${NC}"
# Erstelle temporäre Datei
TMP_FILE=$(mktemp)

cat > "$TMP_FILE" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${TGI_DEPLOYMENT_NAME}-test
  namespace: ${NAMESPACE}
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
      - key: "${GPU_TYPE}"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: tgi
        image: ghcr.io/huggingface/text-generation-inference:1.2.0
        imagePullPolicy: IfNotPresent
        command:
        - "text-generation-launcher"
        args:
        - "--model-id=TinyLlama/TinyLlama-1.1B-Chat-v1.0"
        - "--port=8000"
        - "--dtype=float16"  # Wir verwenden kein quantize, um Konflikte zu vermeiden
        - "--max-input-length=1024"
        - "--max-total-tokens=2048"
        - "--max-batch-prefill-tokens=2048"
        - "--cuda-memory-fraction=0.8"
        env:
        - name: CUDA_VISIBLE_DEVICES
          value: "0"
        - name: NCCL_DEBUG
          value: "INFO"
        - name: TRANSFORMERS_CACHE
          value: "/data/hf-cache"
        ports:
        - containerPort: 8000
          protocol: TCP
        resources:
          limits:
            memory: "8Gi"
            cpu: "2"
            nvidia.com/gpu: 1
          requests:
            memory: "4Gi"
            cpu: "1"
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
          sizeLimit: 4Gi
---
apiVersion: v1
kind: Service
metadata:
  name: ${TGI_SERVICE_NAME}-test
  namespace: ${NAMESPACE}
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

echo -e "${YELLOW}Starte Test-Deployment mit TinyLlama (kleines Modell)...${NC}"
kubectl apply -f "$TMP_FILE"
rm "$TMP_FILE"

echo -e "\n${BLUE}3. Überwache den Pod-Status...${NC}"
echo -e "${YELLOW}Warte auf Pod-Start (kann einige Minuten dauern)...${NC}"
for i in {1..60}; do
    POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l app=llm-server-test -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$POD_NAME" ]; then
        POD_STATUS=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.phase}')
        if [ "$POD_STATUS" == "Running" ]; then
            echo -e "${GREEN}Pod '$POD_NAME' ist aktiv!${NC}"
            break
        fi
        echo -e "Pod-Status: $POD_STATUS"
    else
        echo -e "Warte auf Pod-Erstellung..."
    fi
    sleep 10
    if [ $i -eq 60 ]; then
        echo -e "${RED}Zeitüberschreitung beim Warten auf den Pod.${NC}"
        PODS=$(kubectl -n "$NAMESPACE" get pods)
        echo "Aktuelle Pods:"
        echo "$PODS"
        exit 1
    fi
done

echo -e "\n${BLUE}4. Prüfe GPU-Funktionalität...${NC}"
NVIDIA_SMI_OUTPUT=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi 2>/dev/null)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ NVIDIA GPU wurde erfolgreich erkannt!${NC}"
    echo "$NVIDIA_SMI_OUTPUT" | head -n 15
else
    echo -e "${RED}✗ Konnte nvidia-smi nicht ausführen. GPU möglicherweise nicht verfügbar.${NC}"
    kubectl -n "$NAMESPACE" logs "$POD_NAME"
    exit 1
fi

echo -e "\n${BLUE}5. Überwache TGI-Startup-Logs...${NC}"
echo -e "${YELLOW}Prüfe, ob das Modell erfolgreich geladen wird...${NC}"
for i in {1..40}; do
    LOGS=$(kubectl -n "$NAMESPACE" logs "$POD_NAME" 2>/dev/null)
    if echo "$LOGS" | grep -q "Connected to engine"; then
        echo -e "${GREEN}✓ TGI-Server erfolgreich gestartet!${NC}"
        break
    elif echo "$LOGS" | grep -q "Error"; then
        echo -e "${RED}✗ TGI-Server gestartet mit Fehlern:${NC}"
        echo "$LOGS" | grep -i "error" | tail -n 10
        break
    else
        echo -e "TGI ist noch beim Starten... ($i/40)"
    fi
    sleep 5
    if [ $i -eq 40 ]; then
        echo -e "${YELLOW}Zeitüberschreitung beim Warten auf den TGI-Server.${NC}"
        echo "Aktuelle Logs:"
        kubectl -n "$NAMESPACE" logs "$POD_NAME" | tail -n 20
    fi
done

echo -e "\n${BLUE}6. Memory-Nutzung nach dem Start${NC}"
MEMORY_USAGE=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=memory.used,memory.total --format=csv)
echo "$MEMORY_USAGE"

echo -e "\n${BLUE}7. Empfehlungen für V100-Konfiguration${NC}"
echo -e "${GREEN}Basierend auf den Testergebnissen empfehlen wir:${NC}"
echo -e "1. ${YELLOW}Wichtig: Verwenden Sie entweder --dtype ODER --quantize, aber nicht beides gleichzeitig!${NC}"
echo -e "2. Verwenden Sie kleinere Modelle (2B-7B) mit ${YELLOW}AWQ-Quantisierung${NC} auf V100-GPUs"
echo -e "3. Beschränken Sie Kontextlängen auf ${YELLOW}MAX_INPUT_LENGTH=2048${NC} und ${YELLOW}MAX_TOTAL_TOKENS=4096${NC}"
echo -e "4. Setzen Sie ${YELLOW}CUDA_MEMORY_FRACTION=0.85${NC} für bessere Stabilität"
echo -e "5. Für Multi-GPU-Setups verwenden Sie ${YELLOW}DSHM_SIZE=8Gi${NC} oder höher"
echo -e "6. Nutzen Sie das optimierte Deployment-Skript: ${YELLOW}./scripts/deploy-tgi-v100.sh${NC}"

echo -e "\n${BLUE}8. Bereinige Test-Ressourcen${NC}"
read -p "Möchten Sie das Test-Deployment jetzt entfernen? (J/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Test-Deployment bleibt aktiv für weitere Tests."
else
    echo "Entferne Test-Deployment..."
    kubectl -n "$NAMESPACE" delete deployment "${TGI_DEPLOYMENT_NAME}-test"
    kubectl -n "$NAMESPACE" delete service "${TGI_SERVICE_NAME}-test"
    echo -e "${GREEN}Test-Ressourcen wurden bereinigt.${NC}"
fi

echo -e "\n${GREEN}V100 GPU-Test abgeschlossen.${NC}"
echo -e "Kopieren Sie für optimale Konfiguration die V100-optimierte Beispielkonfiguration:"
echo -e "${YELLOW}cp $ROOT_DIR/configs/config.v100.sh $ROOT_DIR/configs/config.sh${NC}"