#!/bin/bash

# GPU-Kompatibilitätsprüfung für Ollama
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

# Farbdefinitionen
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Hilfsfunktion: Zeige Hilfe an
show_help() {
    echo "Verwendung: $0"
    echo
    echo "GPU-Kompatibilitätsprüfung für Ollama"
    echo
    echo "Dieses Skript überprüft, ob die GPU-Konfiguration korrekt eingerichtet ist"
    echo "und welche GPU-Funktionen in Ollama verfügbar sind."
    echo
    echo "Optionen:"
    echo "  -h, --help        Diese Hilfe anzeigen"
    exit 0
}

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        *)
            echo "Unbekannte Option: $1"
            show_help
            ;;
    esac
done

# Hole den Pod-Namen
POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l service=ollama -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD_NAME" ]; then
    echo -e "${RED}Fehler: Konnte keinen laufenden Ollama Pod finden.${NC}"
    exit 1
fi

echo "=== GPU-Kompatibilitätsprüfung für Ollama ==="
echo "Pod: $POD_NAME"
echo "Namespace: $NAMESPACE"

# Prüfe Kubernetes-Konfiguration
echo -e "\n=== Kubernetes-Konfiguration ==="
K8S_GPU_CONFIG=$(kubectl -n "$NAMESPACE" get deployment "$OLLAMA_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].resources.limits}')
if [[ "$K8S_GPU_CONFIG" == *"nvidia.com/gpu"* ]]; then
    GPU_COUNT=$(kubectl -n "$NAMESPACE" get deployment "$OLLAMA_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.nvidia\.com/gpu}')
    echo -e "${GREEN}✓ GPU konfiguriert in Kubernetes Deployment${NC}"
    echo "  Anzahl GPUs: $GPU_COUNT"
else
    echo -e "${RED}✗ Keine GPU-Konfiguration im Kubernetes Deployment gefunden${NC}"
    echo "  Aktuelle Konfiguration:"
    echo "  $K8S_GPU_CONFIG"
    echo -e "  Stellen Sie sicher, dass 'nvidia.com/gpu' in den Ressourcenlimits definiert ist."
fi

# Prüfe Tolerations
K8S_TOLERATIONS=$(kubectl -n "$NAMESPACE" get deployment "$OLLAMA_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.tolerations}')
if [[ "$K8S_TOLERATIONS" == *"$GPU_TYPE"* ]]; then
    echo -e "${GREEN}✓ GPU-Tolerations konfiguriert${NC}"
    echo "  Typ: $GPU_TYPE"
else
    echo -e "${RED}✗ Keine passenden GPU-Tolerations gefunden${NC}"
    echo "  Konfiguration: $K8S_TOLERATIONS"
    echo -e "  Erwarteter Typ: $GPU_TYPE"
fi

# Prüfe, ob nvidia-smi im Pod verfügbar ist
echo -e "\n=== NVIDIA-Treiber und Utilities ==="
if kubectl -n "$NAMESPACE" exec "$POD_NAME" -- which nvidia-smi &> /dev/null; then
    echo -e "${GREEN}✓ nvidia-smi ist verfügbar${NC}"
    
    # Hole NVIDIA-Treiberversion
    DRIVER_VERSION=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null)
    if [ -n "$DRIVER_VERSION" ]; then
        echo "  Treiberversion: $DRIVER_VERSION"
    else
        echo -e "${YELLOW}⚠ Konnte Treiberversion nicht ermitteln${NC}"
    fi
    
    # Hole CUDA-Version
    CUDA_VERSION=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=cuda_version --format=csv,noheader 2>/dev/null)
    if [ -n "$CUDA_VERSION" ]; then
        echo "  CUDA-Version: $CUDA_VERSION"
    else
        echo -e "${YELLOW}⚠ Konnte CUDA-Version nicht ermitteln${NC}"
    fi
else
    echo -e "${RED}✗ nvidia-smi ist nicht verfügbar${NC}"
    echo "  Überprüfen Sie, ob NVIDIA-Treiber installiert sind und das Pod-Image nvidia-smi unterstützt."
fi

# Prüfe CUDA-Umgebungsvariablen
echo -e "\n=== CUDA-Umgebungsvariablen ==="
LD_LIBRARY_PATH=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c 'echo $LD_LIBRARY_PATH')
if [[ "$LD_LIBRARY_PATH" == */usr/local/nvidia/lib* ]]; then
    echo -e "${GREEN}✓ LD_LIBRARY_PATH ist korrekt konfiguriert${NC}"
    echo "  $LD_LIBRARY_PATH"
else
    echo -e "${YELLOW}⚠ LD_LIBRARY_PATH scheint nicht optimal konfiguriert zu sein${NC}"
    echo "  Aktuell: $LD_LIBRARY_PATH"
    echo "  Erwartet: /usr/local/nvidia/lib:/usr/local/nvidia/lib64:..."
fi

NVIDIA_CAPABILITIES=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c 'echo $NVIDIA_DRIVER_CAPABILITIES')
if [[ "$NVIDIA_CAPABILITIES" == *"compute"* ]]; then
    echo -e "${GREEN}✓ NVIDIA_DRIVER_CAPABILITIES ist korrekt konfiguriert${NC}"
    echo "  $NVIDIA_CAPABILITIES"
else
    echo -e "${YELLOW}⚠ NVIDIA_DRIVER_CAPABILITIES scheint nicht optimal konfiguriert zu sein${NC}"
    echo "  Aktuell: $NVIDIA_CAPABILITIES"
    echo "  Erwartet: compute,utility"
fi

# Prüfe GPU-Hardware
echo -e "\n=== GPU-Hardware-Informationen ==="
GPU_INFO=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=name,memory.total,memory.free,compute_cap --format=csv 2>/dev/null)
if [ -n "$GPU_INFO" ]; then
    echo "$GPU_INFO" | sed '1!b;s/name/GPU-Modell/' | column -t -s, | sed '1s/^/  /' | sed '1!s/^/  /'
    
    # Prüfe Speicherauslastung
    MEM_TOTAL=$(echo "$GPU_INFO" | tail -n 1 | cut -d, -f2 | sed 's/ MiB//')
    MEM_FREE=$(echo "$GPU_INFO" | tail -n 1 | cut -d, -f3 | sed 's/ MiB//')
    MEM_USED=$((MEM_TOTAL - MEM_FREE))
    MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))
    
    if [ "$MEM_PERCENT" -lt 50 ]; then
        echo -e "  ${GREEN}✓ Ausreichend freier GPU-Speicher (${MEM_PERCENT}% belegt)${NC}"
    elif [ "$MEM_PERCENT" -lt 80 ]; then
        echo -e "  ${YELLOW}⚠ GPU-Speicher teilweise belegt (${MEM_PERCENT}% belegt)${NC}"
    else
        echo -e "  ${RED}✗ GPU-Speicher stark ausgelastet (${MEM_PERCENT}% belegt)${NC}"
    fi
else
    echo -e "${RED}✗ Konnte keine GPU-Informationen abrufen${NC}"
fi

# Prüfe Zugriff auf CUDA-Bibliotheken
echo -e "\n=== CUDA-Bibliotheken ==="
CUDA_LIBS=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- bash -c 'ls -la /usr/local/cuda/lib64/*.so 2>/dev/null || echo "Keine CUDA-Bibliotheken gefunden"')
if [[ "$CUDA_LIBS" != *"Keine CUDA-Bibliotheken gefunden"* ]]; then
    echo -e "${GREEN}✓ CUDA-Bibliotheken verfügbar${NC}"
    CUDA_LIB_COUNT=$(echo "$CUDA_LIBS" | wc -l)
    echo "  $CUDA_LIB_COUNT Bibliotheken gefunden in /usr/local/cuda/lib64/"
    
    # Prüfe wichtige CUDA-Bibliotheken
    IMPORTANT_LIBS=("libcudart" "libcublas" "libcublasLt" "libcufft" "libcurand")
    for lib in "${IMPORTANT_LIBS[@]}"; do
        if echo "$CUDA_LIBS" | grep -q "$lib"; then
            echo -e "  ${GREEN}✓ $lib gefunden${NC}"
        else
            echo -e "  ${YELLOW}⚠ $lib nicht gefunden${NC}"
        fi
    done
else
    echo -e "${YELLOW}⚠ Keine CUDA-Bibliotheken in /usr/local/cuda/lib64/ gefunden${NC}"
    echo "  Möglicherweise ist CUDA nicht installiert oder in einem anderen Verzeichnis."
fi

# Überprüfe Ollama API vom lokalen System
echo -e "\n=== Ollama API-Test ==="
# Starte temporäres Port-Forwarding
PORT_FWD_PID=""
cleanup() {
    if [ -n "$PORT_FWD_PID" ]; then
        kill $PORT_FWD_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "Starte temporäres Port-Forwarding für API-Test..."
kubectl -n "$NAMESPACE" port-forward "svc/$OLLAMA_SERVICE_NAME" 11434:11434 &>/dev/null &
PORT_FWD_PID=$!
sleep 2

# Teste die Ollama API vom lokalen System aus
API_RESPONSE=$(curl -s http://localhost:11434/api/tags 2>/dev/null)
if [ -n "$API_RESPONSE" ]; then
    echo -e "${GREEN}✓ Ollama API ist erreichbar${NC}"
    
    # Versuche, die Modelle zu extrahieren (mit und ohne jq)
    if command -v jq &> /dev/null; then
        MODELS=$(echo "$API_RESPONSE" | jq -r '.models[].name' 2>/dev/null)
        if [ -n "$MODELS" ]; then
            MODEL_COUNT=$(echo "$MODELS" | wc -l)
            echo "  $MODEL_COUNT Modelle verfügbar:"
            echo "$MODELS" | sed 's/^/  - /'
            API_TEST="Erfolgreich ($MODEL_COUNT Modelle)"
        else
            echo "  Keine Modelle verfügbar oder Antwort hat unerwartetes Format."
            API_TEST="Erreichbar, aber keine Modelle gefunden"
        fi
    else
        # Einfache Prüfung ohne jq
        if [[ "$API_RESPONSE" == *"models"* ]]; then
            echo "  API antwortet mit Modell-Informationen"
            echo "  Für detaillierte Modell-Liste installieren Sie jq"
            API_TEST="Erfolgreich (Format unbekannt)"
        else
            echo "  API antwortet, aber Format ist unbekannt"
            API_TEST="Erreichbar, Format unbekannt"
        fi
    fi
    
    # Empfehlung für Inferenztests
    echo -e "\n${YELLOW}Empfehlung: Führen Sie einen Inferenztest durch:${NC}"
    echo "  ./scripts/test-gpu.sh"
    echo "oder"
    echo "  ./scripts/benchmark-gpu.sh"
    
else
    echo -e "${RED}✗ Ollama API ist nicht erreichbar${NC}"
    echo "  Überprüfen Sie, ob der Ollama-Server läuft und die Netzwerkkonfiguration korrekt ist."
    API_TEST="Nicht erreichbar"
fi

# Überprüfe, ob im Container curl installiert ist
if kubectl -n "$NAMESPACE" exec "$POD_NAME" -- which curl &> /dev/null; then
    CURL_STATUS="${GREEN}Verfügbar${NC}"
else
    CURL_STATUS="${YELLOW}Nicht verfügbar${NC}"
    echo -e "\n${YELLOW}⚠ curl ist nicht im Container installiert${NC}"
    echo "  Einige API-Tests im Container werden nicht funktionieren."
    echo "  Dies beeinträchtigt jedoch nicht die GPU-Funktionalität von Ollama."
fi

# Zusammenfassung
echo -e "\n=== Zusammenfassung ==="
if kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi &> /dev/null; then
    GPU_STATUS="${GREEN}Verfügbar${NC}"
else
    GPU_STATUS="${RED}Nicht verfügbar${NC}"
fi

echo -e "GPU-Hardware:      $GPU_STATUS"
echo -e "K8s-Konfiguration: $(if [[ "$K8S_GPU_CONFIG" == *"nvidia.com/gpu"* ]]; then echo -e "${GREEN}Korrekt${NC}"; else echo -e "${RED}Fehlerhaft${NC}"; fi)"
echo -e "CUDA-Bibliotheken: $(if [[ "$CUDA_LIBS" != *"Keine CUDA-Bibliotheken gefunden"* ]]; then echo -e "${GREEN}Verfügbar${NC}"; else echo -e "${YELLOW}Nicht gefunden${NC}"; fi)"
echo -e "Ollama API:        $API_TEST"
echo -e "curl im Container: $CURL_STATUS"

echo
if [[ "$GPU_STATUS" == *"Verfügbar"* ]] && [[ "$K8S_GPU_CONFIG" == *"nvidia.com/gpu"* ]]; then
    echo -e "${GREEN}GPU-Konfiguration scheint korrekt zu sein.${NC}"
    echo "Führen Sie einen vollständigen GPU-Test durch, um die Funktionalität zu überprüfen:"
    echo "  ./scripts/test-gpu.sh"
else
    echo -e "${RED}GPU-Konfiguration weist Probleme auf.${NC}"
    echo "Bitte überprüfen Sie die oben genannten Probleme und stellen Sie sicher, dass:"
    echo "1. Die GPU-Tolerations in config.sh korrekt konfiguriert sind"
    echo "2. Umgebungsvariablen für CUDA in deploy-ollama.sh korrekt gesetzt sind"
    echo "3. Das Ollama-Image GPU-Unterstützung bietet"
fi
