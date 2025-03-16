#!/bin/bash

# Skript zum Deployment von HuggingChat mit Verbindung zum bereits laufenden TGI-Server
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

# Erstelle temporäre YAML-Datei für das MongoDB Deployment
MONGO_TMP_FILE=$(mktemp)

# Erstelle YAML für MongoDB Deployment
cat << EOF > "$MONGO_TMP_FILE"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongodb-for-huggingchat
  namespace: $NAMESPACE
  labels:
    app: mongodb-for-huggingchat
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mongodb-for-huggingchat
  template:
    metadata:
      labels:
        app: mongodb-for-huggingchat
    spec:
      containers:
        - image: mongo:latest
          name: mongodb
          ports:
            - containerPort: 27017
              protocol: TCP
          resources:
            limits:
              memory: "1Gi"
              cpu: "500m"
          volumeMounts:
            - name: mongodb-data
              mountPath: /data/db
      volumes:
        - name: mongodb-data
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-for-huggingchat
  namespace: $NAMESPACE
  labels:
    app: mongodb-for-huggingchat
spec:
  ports:
    - name: mongodb
      port: 27017
      protocol: TCP
      targetPort: 27017
  selector:
    app: mongodb-for-huggingchat
  type: ClusterIP
EOF

# Anwenden der MongoDB-Konfiguration
echo "Deploying MongoDB für HuggingChat zu Namespace $NAMESPACE..."
kubectl apply -f "$MONGO_TMP_FILE"

# Aufräumen
rm "$MONGO_TMP_FILE"

# Erstelle temporäre YAML-Datei für das HuggingChat Deployment
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

# Erstelle YAML für HuggingChat Deployment mit Verbindung zum bestehenden TGI-Server
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
            # Verwende die externe URL für den bereits laufenden TGI-Server
            - name: HF_API_URL
              value: "http://host.docker.internal:8000/v1"
            - name: DEFAULT_MODEL
              value: "${MODEL_NAME}"$HUGGINGCHAT_API_KEY_ENV$HUGGINGCHAT_HF_TOKEN_ENV
            - name: ENABLE_EXPERIMENTAL_FEATURES
              value: "true"
            - name: ENABLE_THEMING
              value: "true"
            # MongoDB Verbindung hinzufügen
            - name: MONGODB_URL
              value: "mongodb://mongodb-for-huggingchat:27017/huggingchat"
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

# Warte auf MongoDB-Deployment
echo "Warte auf MongoDB Deployment..."
kubectl -n "$NAMESPACE" rollout status deployment/mongodb-for-huggingchat --timeout=300s

# Anwenden der HuggingChat-Konfiguration
echo "Deploying HuggingChat zu Namespace $NAMESPACE..."
echo "Rollout-Strategie: Recreate (100% Ressourcennutzung)"
echo "Verbindung zum existierenden TGI-Server auf host.docker.internal:8000"
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
echo "HINWEIS: HuggingChat verbindet sich automatisch mit dem bestehenden TGI-Server auf host.docker.internal:8000"
echo "HINWEIS: Der UI verwendet das Modell: $MODEL_NAME"
echo "HINWEIS: MongoDB ist als Datenbank konfiguriert auf mongodb://mongodb-for-huggingchat:27017/huggingchat"
echo "Überwachen Sie den Status mit: kubectl -n $NAMESPACE get pods"
echo "Für direkten Zugriff führen Sie aus: kubectl -n $NAMESPACE port-forward svc/$WEBUI_SERVICE_NAME 3000:3000"