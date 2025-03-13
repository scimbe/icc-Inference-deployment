#!/bin/bash

# Skript zum Testen der GPU-Funktionalität im TGI Pod
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

# Überprüfe ob das TGI Deployment existiert
if ! kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: TGI Deployment '$TGI_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

# Überprüfe ob GPU aktiviert ist
if [ "$USE_GPU" != "true" ]; then
    echo "Fehler: GPU-Unterstützung ist in der Konfiguration nicht aktiviert."
    echo "Bitte setzen Sie USE_GPU=true in Ihrer config.sh."
    exit 1
fi

# Hole den Pod-Namen
POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l app=llm-server -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD_NAME" ]; then
    echo "Fehler: Konnte keinen laufenden TGI Pod finden."
    exit 1
fi

echo "Teste GPU-Verfügbarkeit im Pod '$POD_NAME'..."

# Führe nvidia-smi im Pod aus
echo -e "\n=== NVIDIA-SMI Ausgabe ==="
if kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi; then
    echo -e "\n✅ NVIDIA GPU erfolgreich erkannt und verfügbar!"
else
    echo -e "\n❌ Fehler: nvidia-smi konnte nicht ausgeführt werden. GPU möglicherweise nicht verfügbar."
    exit 1
fi

# Prüfe Umgebungsvariablen für CUDA
echo -e "\n=== CUDA Umgebungsvariablen ==="
echo "LD_LIBRARY_PATH:"
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c 'echo $LD_LIBRARY_PATH'
echo "NVIDIA_DRIVER_CAPABILITIES:"
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c 'echo $NVIDIA_DRIVER_CAPABILITIES'

# Prüfe TGI-spezifische Informationen
echo -e "\n=== TGI Konfiguration ==="
# Extrahiere die args des TGI-Containers
TGI_ARGS=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.spec.containers[0].args}')
echo "TGI Startparameter:"
echo "$TGI_ARGS" | tr -d '[],"' | tr ' ' '\n' | grep -v "^$" | sed 's/^/- /'

# GPU-Anzahl und Multi-GPU-Setup prüfen
GPU_COUNT=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.spec.containers[0].resources.limits.nvidia\.com/gpu}')
echo -e "\nGPU Konfiguration:"
echo "- Zugewiesene GPUs: $GPU_COUNT"

if echo "$TGI_ARGS" | grep -q "sharded"; then
    echo "- Sharded Modus: Aktiviert (für Multi-GPU-Nutzung)"
    
    if [ "$GPU_COUNT" -lt 2 ]; then
        echo "⚠️ Warnung: Sharded-Modus ist aktiviert, aber nur $GPU_COUNT GPU zugewiesen"
        echo "   Dies kann zu Problemen führen. Für Sharded-Modus werden mindestens 2 GPUs empfohlen."
    fi
else
    if [ "$GPU_COUNT" -gt 1 ]; then
        echo "⚠️ Warnung: Mehrere GPUs ($GPU_COUNT) sind zugewiesen, aber Sharded-Modus ist nicht aktiviert."
        echo "   Dies kann zu suboptimaler GPU-Nutzung führen."
    else
        echo "- Sharded-Modus: Nicht aktiviert (nur eine GPU)"
    fi
fi

# Teste TGI API
echo -e "\n=== TGI API Test ==="
# Starte temporäres Port-Forwarding
PORT_FWD_PID=""
cleanup() {
    if [ -n "$PORT_FWD_PID" ]; then
        kill $PORT_FWD_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "Starte temporäres Port-Forwarding für API-Test..."
kubectl -n "$NAMESPACE" port-forward "svc/$TGI_SERVICE_NAME" 3333:3333 &>/dev/null &
PORT_FWD_PID=$!
sleep 2

# Prüfe, ob der TGI-Server API-Anfragen beantwortet
if curl -s http://localhost:3333/v1/models &> /dev/null; then
    MODEL_INFO=$(curl -s http://localhost:3333/v1/models)
    echo "✅ TGI API funktioniert korrekt."
    echo "Modell-Information:"
    echo "$MODEL_INFO" | grep -o '"id":"[^"]*"' | sed 's/"id":"//;s/"//g' | sed 's/^/- /'
else
    echo "❌ TGI API antwortet nicht wie erwartet."
    echo "Der Server lädt möglicherweise noch das Modell oder ist nicht bereit."
    echo "Überprüfen Sie die Logs mit: kubectl -n $NAMESPACE logs $POD_NAME"
fi

# Optional: Einfacher Inferenztest mit einem geladenen Modell
echo -e "\n=== GPU-Inferenztest (optional) ==="
read -p "Möchten Sie einen GPU-Inferenztest durchführen? (j/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Jj]$ ]]; then
    # Überprüfe, ob API erreichbar ist und das Modell geladen ist
    if curl -s http://localhost:3333/v1/models &> /dev/null; then
        echo "Führe Inferenztest durch..."
        
        # Zeitmessung für Inference beginnen
        START_TIME=$(date +%s.%N)
        
        # Führe einen einfachen Chat-Completion aus
        curl -s http://localhost:3333/v1/chat/completions \
          -H "Content-Type: application/json" \
          -d '{
            "model": "'$MODEL_NAME'",
            "messages": [{"role": "user", "content": "Antworte in einem kurzen Satz: Was ist eine GPU?"}],
            "max_tokens": 100,
            "temperature": 0.7
          }' | grep -o '"content":"[^"]*"' | sed 's/"content":"//;s/"//g'
        
        # Zeitmessung beenden
        END_TIME=$(date +%s.%N)
        DURATION=$(echo "$END_TIME - $START_TIME" | bc)
        echo "Inferenz-Dauer: $DURATION Sekunden"
    else
        echo "❌ Inferenztest konnte nicht durchgeführt werden, da die API nicht erreichbar ist."
        echo "Überprüfen Sie die Logs und den Status des TGI-Pods."
    fi
fi

# GPU-Auslastung anzeigen
echo -e "\n=== Aktuelle GPU-Auslastung ==="
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total --format=csv

echo -e "\nGPU-Test abgeschlossen."
