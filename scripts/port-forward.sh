#!/bin/bash

# Skript zum Starten des Port-Forwardings für LLM-Server und WebUI
set -e

# Farbdefinitionen für bessere Lesbarkeit
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Lade Konfiguration
CONFIG_FILE="$ROOT_DIR/configs/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo -e "${RED}FEHLER: config.sh nicht gefunden.${NC}"
    echo -e "Bitte kopieren Sie config.v100.sh nach config.sh und passen Sie die Werte an."
    exit 1
fi

# Engine-Typ bestimmen
ENGINE_TYPE=${ENGINE_TYPE:-"tgi"}
LLM_SERVICE_NAME=""
ENGINE_LABEL=""

case "$ENGINE_TYPE" in
    "tgi")
        LLM_SERVICE_NAME="${TGI_SERVICE_NAME:-inf-service}"
        ENGINE_NAME="Text Generation Inference"
        ENGINE_LABEL="tgi"
        ;;
    "vllm")
        LLM_SERVICE_NAME="${VLLM_SERVICE_NAME:-vllm-service}"
        ENGINE_NAME="vLLM"
        ENGINE_LABEL="vllm"
        ;;
    *)
        echo -e "${RED}Ungültiger ENGINE_TYPE: $ENGINE_TYPE${NC}"
        echo -e "Erlaubte Werte: 'tgi' oder 'vllm'"
        exit 1
        ;;
esac

echo -e "${BLUE}Engine erkannt: $ENGINE_NAME ($ENGINE_TYPE)${NC}"
echo -e "Service-Namen:"
echo -e "- LLM-Service: $LLM_SERVICE_NAME"
echo -e "- WebUI-Service: $WEBUI_SERVICE_NAME"

# Überprüfe ob die Deployments existieren
if ! kubectl -n "$NAMESPACE" get service "$LLM_SERVICE_NAME" &> /dev/null; then
    echo -e "${RED}FEHLER: $ENGINE_NAME Service '$LLM_SERVICE_NAME' nicht gefunden.${NC}"
    echo -e "Bitte überprüfen Sie, ob das Deployment erfolgreich war."
    echo -e "Verfügbare Services im Namespace $NAMESPACE:"
    kubectl -n "$NAMESPACE" get services
    exit 1
fi

if ! kubectl -n "$NAMESPACE" get service "$WEBUI_SERVICE_NAME" &> /dev/null; then
    echo -e "${YELLOW}WARNUNG: WebUI Service '$WEBUI_SERVICE_NAME' nicht gefunden.${NC}"
    echo -e "Es wird nur das Port-Forwarding für die API eingerichtet."
    echo -e "Verfügbare Services im Namespace $NAMESPACE:"
    kubectl -n "$NAMESPACE" get services
    WEB_UI_AVAILABLE=false
else
    WEB_UI_AVAILABLE=true
fi

# Prüfe, ob die WebUI-Pods laufen
if [ "$WEB_UI_AVAILABLE" = true ]; then
    WEBUI_POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l "service=${ENGINE_LABEL}-webui" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$WEBUI_POD_NAME" ]; then
        echo -e "${YELLOW}WARNUNG: WebUI-Pod wurde nicht gefunden.${NC}"
        echo -e "Port-Forwarding wird möglicherweise nicht funktionieren."
        echo -e "Verfügbare Pods im Namespace $NAMESPACE:"
        kubectl -n "$NAMESPACE" get pods
    else
        WEBUI_POD_STATUS=$(kubectl -n "$NAMESPACE" get pod "$WEBUI_POD_NAME" -o jsonpath='{.status.phase}')
        echo -e "WebUI-Pod: $WEBUI_POD_NAME ($WEBUI_POD_STATUS)"

        # Prüfen, ob der Port 3000 im Container geöffnet ist
        echo -e "${BLUE}Prüfe, ob der WebUI-Pod auf Port 3000 lauscht...${NC}"
        if kubectl -n "$NAMESPACE" exec "$WEBUI_POD_NAME" -- netstat -tulpn 2>/dev/null | grep -q ":3000"; then
            echo -e "${GREEN}Port 3000 ist aktiv im WebUI-Pod.${NC}"
        else
            echo -e "${YELLOW}WARNUNG: Konnte Port 3000 nicht im WebUI-Pod überprüfen.${NC}"
            echo -e "Möglicherweise fehlt netstat im Container oder es gibt ein anderes Problem."
            echo -e "Überprüfen Sie die Container-Logs mit: kubectl -n $NAMESPACE logs $WEBUI_POD_NAME"
        fi
    fi
fi

# Verwende verfügbare Ports
API_PORT=8000
WEBUI_PORT=3010  # Anderer Port als Standard, um Konflikte zu vermeiden

# Parameter verarbeiten
for arg in "$@"; do
    case $arg in
        --api-port=*)
        API_PORT="${arg#*=}"
        shift
        ;;
        --webui-port=*)
        WEBUI_PORT="${arg#*=}"
        shift
        ;;
    esac
done

# Starte Port-Forwarding in separaten Prozessen
echo -e "${BLUE}=== Port-Forwarding für LLM-Dienste ===${NC}"
echo -e "Starte Port-Forwarding für $ENGINE_NAME API auf Port $API_PORT..."
kubectl -n "$NAMESPACE" port-forward svc/"$LLM_SERVICE_NAME" ${API_PORT}:8000 &
API_PID=$!

if [ "$WEB_UI_AVAILABLE" = true ]; then
    echo -e "Starte Port-Forwarding für WebUI auf Port $WEBUI_PORT..."

    # Setze Umgebungsvariable für WebSockets-Support
    export KUBECTL_PORT_FORWARD_WEBSOCKETS="true"

    # Starte Port-Forwarding zum Pod statt zum Service (direkter)
    if [ -n "$WEBUI_POD_NAME" ]; then
        kubectl -n "$NAMESPACE" port-forward pod/"$WEBUI_POD_NAME" ${WEBUI_PORT}:3000 &
        echo -e "${GREEN}Port-Forwarding direkt zum WebUI-Pod gestartet.${NC}"
    else
        kubectl -n "$NAMESPACE" port-forward svc/"$WEBUI_SERVICE_NAME" ${WEBUI_PORT}:3000 &
        echo -e "${YELLOW}Port-Forwarding zum WebUI-Service gestartet.${NC}"
    fi
    WEBUI_PID=$!
fi

echo -e "\n${GREEN}Port-Forwarding gestartet:${NC}"
echo -e "🔌 ${ENGINE_NAME} API: ${GREEN}http://localhost:${API_PORT}${NC}"
if [ "$WEB_UI_AVAILABLE" = true ]; then
    echo -e "🌐 WebUI: ${GREEN}http://localhost:${WEBUI_PORT}${NC}"
fi
echo -e "\nDrücken Sie ${YELLOW}CTRL+C${NC}, um das Port-Forwarding zu beenden."

# Funktion zum Aufräumen beim Beenden
cleanup() {
    echo -e "\n${BLUE}Beende Port-Forwarding...${NC}"
    kill $API_PID 2>/dev/null || true
    if [ "$WEB_UI_AVAILABLE" = true ]; then
        kill $WEBUI_PID 2>/dev/null || true
    fi
    exit 0
}

# Registriere Signal-Handler
trap cleanup SIGINT SIGTERM

# Warte auf Benutzerabbruch
wait
