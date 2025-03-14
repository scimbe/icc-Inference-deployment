#!/bin/bash

# Skript zum Deployment von HuggingChat für Text Generation Inference (TGI)
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

# Erstelle temporäre YAML-Datei für das Deployment
TMP_FILE=$(mktemp)

# Umgebungsvariablen für HuggingChat
if [ -n "$TGI_API_KEY" ]; then
    HUGGINGCHAT_API_KEY_ENV="
            - name: API_KEY
              value: \"${TGI_API_KEY}\""
else
    HUGGINGCHAT_API_KEY_ENV=""
fi

# Hugging Face Token, falls vorhanden
if [ -n "$HUGGINGFACE_TOKEN" ]; then
    HUGGINGCHAT_HF_TOKEN_ENV="
            - name: HF_ACCESS_TOKEN
              value: \"${HUGGINGFACE_TOKEN}\""
else
    HUGGINGCHAT_HF_TOKEN_ENV=""
fi

# Erstelle YAML für HuggingChat Deployment
cat << EOF > "$TMP_FILE"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $WEBUI_DEPLOYMENT_NAME
  namespace: $NAMESPACE
  labels:
    service: huggingchat-ui
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      service: huggingchat-ui
  template:
    metadata:
      labels:
        service: huggingchat-ui
    spec:
      containers:
        - image: ghcr.io/huggingface/chat-ui:latest
          name: huggingchat
          env:
            - name: HF_API_URL
              value: "http://$TGI_SERVICE_NAME:8000/v1"
            - name: DEFAULT_MODEL
              value: "${MODEL_NAME}"$HUGGINGCHAT_API_KEY_ENV$HUGGINGCHAT_HF_TOKEN_ENV
            - name: ENABLE_EXPERIMENTAL_FEATURES
              value: "true"
            - name: ENABLE_THEMING
              value: "true"
          ports:
            - containerPort: 3000
              protocol: TCP
          resources:
            limits:
              memory: "2Gi"
              cpu: "1000m"
          volumeMounts:
            - name: huggingchat-data
              mountPath: /data
      volumes:
        - name: huggingchat-data
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: $WEBUI_SERVICE_NAME
  namespace: $NAMESPACE
  labels:
    service: huggingchat-ui
spec:
  ports:
    - name: http
      port: 3000
      protocol: TCP
      targetPort: 3000
  selector:
    service: huggingchat-ui
  type: ClusterIP
EOF

# Anwenden der Konfiguration
echo "Deploying HuggingChat zu Namespace $NAMESPACE..."
echo "Rollout-Strategie: Recreate (100% Ressourcennutzung)"
echo "Verwendetes Modell: $MODEL_NAME"
echo "Verwendete Konfiguration:"
cat "$TMP_FILE"
echo "---------------------------------"

kubectl apply -f "$TMP_FILE"

# Aufräumen
rm "$TMP_FILE"

# Warte auf das Deployment
echo "Warte auf das HuggingChat Deployment..."
kubectl -n "$NAMESPACE" rollout status deployment/"$WEBUI_DEPLOYMENT_NAME" --timeout=300s

echo "HuggingChat Deployment erfolgreich."
echo "Service erreichbar über: $WEBUI_SERVICE_NAME:3000"
echo
echo "HINWEIS: HuggingChat verbindet sich automatisch mit dem TGI-Server über die OpenAI-kompatible API."
echo "HINWEIS: Der UI verwendet das Modell: $MODEL_NAME"
echo "Überwachen Sie den Status mit: kubectl -n $NAMESPACE get pods"
echo "Für direkten Zugriff führen Sie aus: kubectl -n $NAMESPACE port-forward svc/$WEBUI_SERVICE_NAME 3000:3000"
