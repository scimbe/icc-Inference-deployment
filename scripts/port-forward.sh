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
    exit 1
fi

# Engine-Typ bestimmen
ENGINE_TYPE=${ENGINE_TYPE:-"tgi"}
LLM_SERVICE_NAME=""

case "$ENGINE_TYPE" in
    "tgi")
        LLM_SERVICE_NAME="$TGI_SERVICE_NAME"
        ENGINE_NAME="Text Generation Inference"
        ;;
    "vllm")
        LLM_SERVICE_NAME="vllm-service"
        ENGINE_NAME="vLLM"
        ;;
    *)
        echo -e "${RED}Ungültiger ENGINE_TYPE: $ENGINE_TYPE${NC}"
        echo -e "Erlaubte Werte: 'tgi' oder 'vllm'"
        exit 1
        ;;
esac

# Überprüfe ob die Deployments existieren
if ! kubectl -n "$NAMESPACE" get service "$LLM_SERVICE_NAME" &> /dev/null; then
    echo -e "${RED}FEHLER: $ENGINE_NAME Service '$LLM_SERVICE_NAME' nicht gefunden.${NC}"
    echo -e "Bitte überprüfen Sie, ob das Deployment erfolgreich war."
    exit 1
fi

if ! kubectl -n "$NAMESPACE" get service "$WEBUI_SERVICE_NAME" &> /dev/null; then
    echo -e "${YELLOW}WARNUNG: WebUI Service '$WEBUI_SERVICE_NAME' nicht gefunden.${NC}"
    echo -e "Es wird nur das Port-Forwarding für die API eingerichtet."
    WEB_UI_AVAILABLE=false
else
    WEB_UI_AVAILABLE=true
fi

# Verwende verfügbare Ports
API_PORT=8000
WEBUI_PORT=3000

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
    export KUBECTL_PORT_FORWARD_WEBSOCKETS="true"
    kubectl -n "$NAMESPACE" port-forward svc/"$WEBUI_SERVICE_NAME" ${WEBUI_PORT}:3000 &
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
