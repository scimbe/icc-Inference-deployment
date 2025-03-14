#!/bin/bash

# Skript zum Starten des Port-Forwardings für TGI und WebUI
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
if ! kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: TGI Deployment '$TGI_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

if ! kubectl -n "$NAMESPACE" get deployment "$WEBUI_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: WebUI Deployment '$WEBUI_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

# Starte Port-Forwarding in separaten Prozessen
echo "Starte Port-Forwarding für TGI auf Port 8000..."
kubectl -n "$NAMESPACE" port-forward svc/"$TGI_SERVICE_NAME" 8000:8000 &
TGI_PID=$!

echo "Starte Port-Forwarding für WebUI auf Port 3000..."
export KUBECTL_PORT_FORWARD_WEBSOCKETS="true"
kubectl -n "$NAMESPACE" port-forward svc/"$WEBUI_SERVICE_NAME" 3000:3000 &
WEBUI_PID=$!

echo "Port-Forwarding gestartet."
echo "TGI API: http://localhost:8000"
echo "WebUI: http://localhost:3000"
echo "Drücken Sie CTRL+C, um das Port-Forwarding zu beenden."

# Funktion zum Aufräumen beim Beenden
cleanup() {
    echo "Beende Port-Forwarding..."
    kill $TGI_PID $WEBUI_PID 2>/dev/null || true
    exit 0
}

# Registriere Signal-Handler
trap cleanup SIGINT SIGTERM

# Warte auf Benutzerabbruch
wait