#!/bin/bash

# Skript zum Starten des Port-Forwardings für vLLM und WebUI
# Angepasst für vLLM auf Port 3333
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

# Überprüfe ob die Deployments existieren
if ! kubectl -n "$NAMESPACE" get deployment "$VLLM_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: vLLM Deployment '$VLLM_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

if ! kubectl -n "$NAMESPACE" get deployment "$WEBUI_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: WebUI Deployment '$WEBUI_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

# Starte Port-Forwarding in separaten Prozessen
echo "Starte Port-Forwarding für vLLM auf Port 3333..."
kubectl -n "$NAMESPACE" port-forward svc/"$VLLM_SERVICE_NAME" 3333:3333 &
VLLM_PID=$!

echo "Starte Port-Forwarding für WebUI auf Port 8080..."
export KUBECTL_PORT_FORWARD_WEBSOCKETS="true"
kubectl -n "$NAMESPACE" port-forward svc/"$WEBUI_SERVICE_NAME" 8080:8080 &
WEBUI_PID=$!

echo "Port-Forwarding gestartet."
echo "vLLM API: http://localhost:3333"
echo "WebUI: http://localhost:8080"
echo "Drücken Sie CTRL+C, um das Port-Forwarding zu beenden."

# Funktion zum Aufräumen beim Beenden
cleanup() {
    echo "Beende Port-Forwarding..."
    kill $VLLM_PID $WEBUI_PID 2>/dev/null || true
    exit 0
}

# Registriere Signal-Handler
trap cleanup SIGINT SIGTERM

# Warte auf Benutzerabbruch
wait
