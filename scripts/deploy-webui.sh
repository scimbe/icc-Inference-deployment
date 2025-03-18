#!/bin/bash

# Skript zum Deployment der Open WebUI für Text Generation Inference (TGI) oder vLLM
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
    echo -e "Bitte kopieren Sie config.v100.sh nach config.sh und passen Sie die Werte an."
    exit 1
fi

# Engine-Typ und Service-Namen bestimmen
ENGINE_TYPE=${ENGINE_TYPE:-"tgi"}
LLM_SERVICE_NAME=""
LLM_SERVICE_LABEL=""

case "$ENGINE_TYPE" in
    "tgi")
        LLM_SERVICE_NAME="${TGI_SERVICE_NAME:-inf-service}"
        LLM_SERVICE_LABEL="app=llm-server"
        ENGINE_LABEL="tgi"
        echo -e "${BLUE}Engine: Text Generation Inference (TGI)${NC}"
        ;;
    "vllm")
        LLM_SERVICE_NAME="${VLLM_SERVICE_NAME:-vllm-service}"
        LLM_SERVICE_LABEL="service=vllm-server"
        ENGINE_LABEL="vllm"
        echo -e "${BLUE}Engine: vLLM${NC}"
        ;;
    *)
        echo -e "${RED}Ungültiger ENGINE_TYPE: $ENGINE_TYPE${NC}"
        echo -e "Erlaubte Werte: 'tgi' oder 'vllm'"
        exit 1
        ;;
esac

# Prüfen, ob der LLM-Service existiert
echo -e "${BLUE}Prüfe, ob der LLM-Service $LLM_SERVICE_NAME existiert...${NC}"
if ! kubectl -n "$NAMESPACE" get service "$LLM_SERVICE_NAME" &> /dev/null; then
    echo -e "${RED}Fehler: LLM-Service '$LLM_SERVICE_NAME' nicht gefunden.${NC}"
    echo -e "Bitte führen Sie zuerst deploy-${ENGINE_TYPE}-v100.sh aus."
    exit 1
fi

# Erstelle temporäre YAML-Datei für das Deployment
TMP_FILE=$(mktemp)

# WebUI-Konfiguration mit API_KEY
if [ -n "$TGI_API_KEY" ]; then
    WEBUI_API_KEY_ENV="
            - name: OPENAI_API_KEY
              value: \"${TGI_API_KEY}\""
else
    WEBUI_API_KEY_ENV=""
fi

# Erstelle YAML für WebUI Deployment
cat << EOF > "$TMP_FILE"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $WEBUI_DEPLOYMENT_NAME
  namespace: $NAMESPACE
  labels:
    service: ${ENGINE_LABEL}-webui
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      service: ${ENGINE_LABEL}-webui
  template:
    metadata:
      labels:
        service: ${ENGINE_LABEL}-webui
    spec:
      containers:
        - image: ghcr.io/open-webui/open-webui:main
          name: webui
          env:
            - name: ENABLE_OLLAMA_API
              value: "false"
            - name: OPENAI_API_BASE_URL
              value: "http://$LLM_SERVICE_NAME:8000/v1"$WEBUI_API_KEY_ENV
            - name: ENABLE_RAG_WEB_SEARCH
              value: "false"
            - name: ENABLE_IMAGE_GENERATION
              value: "false"
            - name: DEBUG
              value: "true"
          ports:
            - containerPort: 3000
              protocol: TCP
          resources:
            limits:
              memory: "2Gi"
              cpu: "1000m"
          volumeMounts:
            - name: webui-data
              mountPath: /app/backend/data
          readinessProbe:
            httpGet:
              path: /
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 3
      volumes:
        - name: webui-data
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: $WEBUI_SERVICE_NAME
  namespace: $NAMESPACE
  labels:
    service: ${ENGINE_LABEL}-webui
spec:
  ports:
    - name: http
      port: 3000
      protocol: TCP
      targetPort: 3000
  selector:
    service: ${ENGINE_LABEL}-webui
  type: ClusterIP
EOF

# Anwenden der Konfiguration
echo -e "${BLUE}Deploying Open WebUI zu Namespace $NAMESPACE...${NC}"
echo -e "Engine: $ENGINE_TYPE (Service: $LLM_SERVICE_NAME)"
echo -e "Rollout-Strategie: Recreate (100% Ressourcennutzung)"

if [ "${DEBUG:-false}" == "true" ]; then
    echo -e "${YELLOW}Verwendete Konfiguration:${NC}"
    cat "$TMP_FILE"
    echo -e "---------------------------------"
fi

kubectl apply -f "$TMP_FILE"

# Aufräumen
rm "$TMP_FILE"

# Warte auf das Deployment
echo -e "${BLUE}Warte auf das WebUI Deployment...${NC}"
kubectl -n "$NAMESPACE" rollout status deployment/"$WEBUI_DEPLOYMENT_NAME" --timeout=300s

# Prüfe, ob das Deployment erfolgreich war
POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l "service=${ENGINE_LABEL}-webui" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD_NAME" ]; then
    echo -e "${RED}Fehler: WebUI-Pod wurde nicht gefunden.${NC}"
    echo -e "Bitte überprüfen Sie die Logs mit: kubectl -n $NAMESPACE get events"
    exit 1
fi

POD_STATUS=$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
    echo -e "${RED}Fehler: WebUI-Pod ist nicht im 'Running'-Status (aktuell: $POD_STATUS).${NC}"
    echo -e "Bitte überprüfen Sie die Logs mit: kubectl -n $NAMESPACE logs $POD_NAME"
    exit 1
fi

echo -e "${GREEN}Open WebUI Deployment erfolgreich.${NC}"
echo -e "Service erreichbar über: $WEBUI_SERVICE_NAME:3000"
echo
echo -e "${YELLOW}Wichtige Hinweise:${NC}"
echo -e "- Die WebUI verbindet sich mit dem $ENGINE_TYPE-Server über die OpenAI-kompatible API"
echo -e "- API-URL: http://$LLM_SERVICE_NAME:8000/v1"
echo -e "- Überwachen Sie den Status mit: kubectl -n $NAMESPACE get pods"
echo -e "- Pod-Logs anzeigen mit: kubectl -n $NAMESPACE logs $POD_NAME"
echo -e "- Für direkten Zugriff auf die WebUI: ${GREEN}kubectl -n $NAMESPACE port-forward svc/$WEBUI_SERVICE_NAME 3010:3000${NC}"
