#!/bin/bash

# Skript zum Bereinigen aller erstellten Ressourcen
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

echo "=== Bereinigung der ICC vLLM Deployment Ressourcen ==="
echo "Namespace: $NAMESPACE"

# Bestätigung einholen
read -p "Sind Sie sicher, dass Sie alle Ressourcen löschen möchten? (j/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Abbruch"
    exit 1
fi

# Lösche Ingress, falls vorhanden
if kubectl -n "$NAMESPACE" get ingress vllm-ingress &> /dev/null; then
    echo "Lösche Ingress..."
    kubectl -n "$NAMESPACE" delete ingress vllm-ingress
fi

# Lösche WebUI Deployment und Service
echo "Lösche WebUI..."
kubectl -n "$NAMESPACE" delete deployment "$WEBUI_DEPLOYMENT_NAME" --ignore-not-found=true
kubectl -n "$NAMESPACE" delete service "$WEBUI_SERVICE_NAME" --ignore-not-found=true

# Lösche vLLM Deployment und Service
echo "Lösche vLLM..."
kubectl -n "$NAMESPACE" delete deployment "$VLLM_DEPLOYMENT_NAME" --ignore-not-found=true
kubectl -n "$NAMESPACE" delete service "$VLLM_SERVICE_NAME" --ignore-not-found=true

echo "Bereinigung abgeschlossen."
echo "Die Ressourcen wurden aus dem Kubernetes Cluster entfernt."
echo
echo "HINWEIS: Falls Sie heruntergeladene Modelle aus dem Cluster entfernen möchten,"
echo "müssen Sie ggf. PersistentVolumeClaims separat löschen:"
echo "kubectl -n $NAMESPACE get pvc"
echo "kubectl -n $NAMESPACE delete pvc <pvc-name>"
