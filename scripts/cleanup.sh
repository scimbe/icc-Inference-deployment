#!/bin/bash

# Skript zum Bereinigen aller erstellten Ressourcen (TGI und vLLM)
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
if [ -f "$ROOT_DIR/configs/config.sh" ]; then
    source "$ROOT_DIR/configs/config.sh"
else
    echo -e "${RED}Fehler: config.sh nicht gefunden.${NC}"
    exit 1
fi

echo -e "${BLUE}=== Bereinigung der ICC LLM Deployment Ressourcen ===${NC}"
echo -e "Namespace: ${YELLOW}$NAMESPACE${NC}"
echo -e "Engine-Typ: ${YELLOW}${ENGINE_TYPE:-tgi}${NC}"

# Bestätigung einholen
read -p "Sind Sie sicher, dass Sie alle Ressourcen löschen möchten? (j/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Abbruch"
    exit 1
fi

# Lösche Ingress, falls vorhanden
if kubectl -n "$NAMESPACE" get ingress tgi-ingress &> /dev/null; then
    echo -e "Lösche Ingress..."
    kubectl -n "$NAMESPACE" delete ingress tgi-ingress
fi

if kubectl -n "$NAMESPACE" get ingress vllm-ingress &> /dev/null; then
    echo -e "Lösche vLLM Ingress..."
    kubectl -n "$NAMESPACE" delete ingress vllm-ingress
fi

# Lösche WebUI Deployment und Service
echo -e "Lösche WebUI..."
kubectl -n "$NAMESPACE" delete deployment "$WEBUI_DEPLOYMENT_NAME" --ignore-not-found=true
kubectl -n "$NAMESPACE" delete service "$WEBUI_SERVICE_NAME" --ignore-not-found=true

# Lösche TGI Deployment und Service
echo -e "Lösche TGI..."
kubectl -n "$NAMESPACE" delete deployment "$TGI_DEPLOYMENT_NAME" --ignore-not-found=true
kubectl -n "$NAMESPACE" delete service "$TGI_SERVICE_NAME" --ignore-not-found=true

# Lösche vLLM Deployment und Service
echo -e "Lösche vLLM..."
kubectl -n "$NAMESPACE" delete deployment "${VLLM_DEPLOYMENT_NAME:-vllm-server}" --ignore-not-found=true
kubectl -n "$NAMESPACE" delete service "${VLLM_SERVICE_NAME:-vllm-service}" --ignore-not-found=true

# Lösche auch Test-Deployments falls vorhanden
echo -e "Lösche Test-Deployments falls vorhanden..."
kubectl -n "$NAMESPACE" delete deployment "${TGI_DEPLOYMENT_NAME}-test" --ignore-not-found=true
kubectl -n "$NAMESPACE" delete service "${TGI_SERVICE_NAME}-test" --ignore-not-found=true
kubectl -n "$NAMESPACE" delete deployment "${VLLM_DEPLOYMENT_NAME}-test" --ignore-not-found=true
kubectl -n "$NAMESPACE" delete service "${VLLM_SERVICE_NAME}-test" --ignore-not-found=true

# Lösche Secrets
echo -e "Lösche Secrets..."
kubectl -n "$NAMESPACE" delete secret huggingface-token --ignore-not-found=true
kubectl -n "$NAMESPACE" delete secret tgi-api-key --ignore-not-found=true

echo -e "${GREEN}Bereinigung abgeschlossen.${NC}"
echo -e "Die Ressourcen wurden aus dem Kubernetes Cluster entfernt."
echo
echo -e "${YELLOW}HINWEIS:${NC} Falls Sie heruntergeladene Modelle aus dem Cluster entfernen möchten,"
echo -e "müssen Sie ggf. PersistentVolumeClaims separat löschen:"
echo -e "kubectl -n $NAMESPACE get pvc"
echo -e "kubectl -n $NAMESPACE delete pvc <pvc-name>"
