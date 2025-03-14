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

# Pod und GPU-Typ prüfen
POD_STATUS=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
    echo "Fehler: Pod ist nicht im 'Running' Status, sondern: $POD_STATUS"
    echo "Überprüfen Sie die Logs mit: kubectl -n $NAMESPACE logs $POD_NAME"
    exit 1
fi

echo "Teste GPU-Verfügbarkeit im Pod '$POD_NAME'..."
echo "GPU-Typ: $GPU_TYPE"
echo "Anzahl GPUs: $GPU_COUNT"

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
echo "CUDA_VISIBLE_DEVICES:"
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c 'echo $CUDA_VISIBLE_DEVICES'

# Prüfe spezifische A100-Variablen
if [ "$GPU_TYPE" == "gpu-tesla-a100" ]; then
    echo -e "\n=== A100-spezifische Konfiguration ==="
    echo "NCCL_P2P_DISABLE:"
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c 'echo $NCCL_P2P_DISABLE || echo "nicht gesetzt"'
    echo "NCCL_IB_DISABLE:"
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c 'echo $NCCL_IB_DISABLE || echo "nicht gesetzt"'
    echo "NCCL_DEBUG:"
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c 'echo $NCCL_DEBUG || echo "nicht gesetzt"'
    echo "TGI_DISABLE_FLASH_ATTENTION:"
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c 'echo $TGI_DISABLE_FLASH_ATTENTION || echo "nicht gesetzt"'
fi

# Prüfe TGI-spezifische Informationen
echo -e "\n=== TGI Konfiguration ==="
# Extrahiere die args des TGI-Containers
TGI_ARGS=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.spec.containers[0].args}')
echo "TGI Startparameter:"
echo "$TGI_ARGS" | tr -d '[],"' | tr ' ' '\n' | grep -v "^$" | sort | sed 's/^/- /'

# GPU-Anzahl und Multi-GPU-Setup prüfen
GPU_COUNT=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.spec.containers[0].resources.limits.nvidia\.com/gpu}')
echo -e "\nGPU Konfiguration:"
echo "- Zugewiesene GPUs: $GPU_COUNT"

# Sharded-Modus überprüfen
if echo "$TGI_ARGS" | grep -q "sharded"; then
    echo -e "${GREEN}✓${NC} Sharded Modus: Aktiviert (für Multi-GPU-Nutzung)"
    
    # Prüfe, ob num-shard korrekt gesetzt ist (für A100)
    if echo "$TGI_ARGS" | grep -q "num-shard"; then
        NUM_SHARD=$(echo "$TGI_ARGS" | grep -o -- "--num-shard=[0-9]*" | cut -d= -f2)
        echo "- Num-Shard: $NUM_SHARD"
        
        if [ "$NUM_SHARD" != "$GPU_COUNT" ]; then
            echo "⚠️ Warnung: num-shard ($NUM_SHARD) unterscheidet sich von der GPU-Anzahl ($GPU_COUNT)"
        fi
    elif [ "$GPU_TYPE" == "gpu-tesla-a100" ] && [ "$GPU_COUNT" -gt 1 ]; then
        echo "⚠️ Warnung: num-shard ist nicht gesetzt für A100 Multi-GPU-Setup"
    fi
    
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

# Shared Memory überprüfen
DSHM_SIZE=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.spec.volumes[?(@.name=="dshm")].emptyDir.sizeLimit}')
echo "- Shared Memory (dshm): $DSHM_SIZE"

if [ "$GPU_COUNT" -gt 1 ] && [[ "$DSHM_SIZE" == "1Gi" || "$DSHM_SIZE" == "2Gi" ]]; then
    echo "⚠️ Warnung: Shared Memory ist möglicherweise zu klein für Multi-GPU-Setup"
    echo "   Empfehlung: Mindestens 8Gi für 2 GPUs, 16Gi für 3-4 GPUs."
    echo "   Erhöhen mit: ./scripts/scale-gpu.sh --mem 16Gi"
fi

if [ "$GPU_TYPE" == "gpu-tesla-a100" ] && [[ "$DSHM_SIZE" == "1Gi" || "$DSHM_SIZE" == "2Gi" || "$DSHM_SIZE" == "4Gi" ]]; then
    echo "⚠️ Warnung: Shared Memory ist möglicherweise zu klein für A100 GPUs"
    echo "   Empfehlung: Mindestens 8Gi für eine A100, 16Gi für Multi-GPU-A100-Setup."
    echo "   Erhöhen mit: ./scripts/scale-gpu.sh --mem 16Gi"
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
sleep 3

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

        # Prüfe und zeige GPU-Nutzung nach Inferenz
        echo -e "\nGPU-Nutzung nach Inferenz:"
        kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total --format=csv
    else
        echo "❌ Inferenztest konnte nicht durchgeführt werden, da die API nicht erreichbar ist."
        echo "Überprüfen Sie die Logs und den Status des TGI-Pods."
    fi
fi

# Prüfe Pod-Logs auf häufige Probleme
echo -e "\n=== Log-Analyse für häufige Probleme ==="
LOG_OUTPUT=$(kubectl -n "$NAMESPACE" logs "$POD_NAME" --tail=100)

# Suche nach häufigen Fehlermustern
if echo "$LOG_OUTPUT" | grep -q "Failed to allocate memory for tensor"; then
    echo "❌ FEHLER: GPU-Speicherzuweisung fehlgeschlagen!"
    echo "   Ursache: Nicht genügend GPU-Speicher für das Modell verfügbar."
    echo "   Lösung: Verwenden Sie mehr GPUs, ein kleineres Modell oder aktivieren Sie Quantisierung."
fi

if echo "$LOG_OUTPUT" | grep -q "Error: Shard process was signaled to shutdown with signal 9"; then
    echo "❌ FEHLER: Shard-Prozess wurde mit Signal 9 (SIGKILL) beendet!"
    echo "   Ursache: Wahrscheinlich Out-of-Memory (OOM) oder Ressourcenbeschränkung."
    echo "   Für A100 GPUs empfohlene Lösungen:"
    echo "   - Erhöhen Sie den Shared Memory: ./scripts/scale-gpu.sh --mem 16Gi"
    echo "   - Setzen Sie TGI_DISABLE_FLASH_ATTENTION=true in config.sh"
    echo "   - Verringern Sie die Batch-Größe oder erhöhen Sie die verfügbaren Ressourcen"
fi

if echo "$LOG_OUTPUT" | grep -q "NCCL error"; then
    echo "❌ FEHLER: NCCL-Kommunikationsfehler zwischen GPUs!"
    echo "   Für A100 GPUs empfohlene Lösungen:"
    echo "   - Stellen Sie sicher, dass NCCL_P2P_DISABLE=1 und NCCL_IB_DISABLE=1 gesetzt sind"
    echo "   - Setzen Sie NUM_SHARD gleich der GPU-Anzahl"
    echo "   - Versuchen Sie es mit einer neuen Deployment: ./scripts/deploy-tgi.sh"
fi

# GPU-Auslastung anzeigen
echo -e "\n=== Aktuelle GPU-Auslastung ==="
kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total --format=csv

echo -e "\nGPU-Test abgeschlossen."
