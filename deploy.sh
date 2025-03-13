#!/bin/bash

# Hauptskript für das Deployment von vLLM und Open WebUI auf der ICC
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Lade Konfiguration
if [ -f "$SCRIPT_DIR/configs/config.sh" ]; then
    source "$SCRIPT_DIR/configs/config.sh"
else
    echo "Fehler: config.sh nicht gefunden. Bitte kopieren Sie configs/config.example.sh nach configs/config.sh und passen Sie die Werte an."
    exit 1
fi

# Prüfe, ob kubectl verfügbar ist
if ! command -v kubectl &> /dev/null; then
    echo "Fehler: kubectl ist nicht installiert oder nicht im PATH."
    echo "Bitte installieren Sie kubectl gemäß der Anleitung: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Prüfe, ob Namespace existiert
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "Fehler: Namespace $NAMESPACE existiert nicht."
    echo "Bitte überprüfen Sie Ihre Konfiguration und stellen Sie sicher, dass Sie bei der ICC eingeloggt sind."
    exit 1
fi

echo "=== ICC vLLM Deployment Starter ==="
echo "Namespace: $NAMESPACE"
echo "GPU-Unterstützung: $([ "$USE_GPU" == "true" ] && echo "Aktiviert ($GPU_TYPE, $GPU_COUNT GPU(s))" || echo "Deaktiviert")"
echo "Modell: $MODEL_NAME"

# Führe Deployment-Skripte aus
echo -e "\n1. Deploying vLLM..."
"$SCRIPT_DIR/scripts/deploy-vllm.sh"

echo -e "\n2. Deploying Open WebUI..."
"$SCRIPT_DIR/scripts/deploy-webui.sh"

echo -e "\n=== Deployment abgeschlossen! ==="
echo "Überprüfen Sie den Status mit: kubectl -n $NAMESPACE get pods"

# Zeige Anweisungen für den Zugriff
echo -e "\n=== Zugriff auf die Dienste ==="
echo "Hinweis: vLLM muss das Modell beim ersten Start herunterladen, was einige Zeit dauern kann."
echo "Überwachen Sie den Fortschritt mit: kubectl -n $NAMESPACE logs -f deployment/$VLLM_DEPLOYMENT_NAME"
echo
echo "Um auf vLLM und die WebUI zuzugreifen, führen Sie aus:"
echo "  ./scripts/port-forward.sh"
echo
echo "Alternativ können Sie auf die einzelnen Dienste separat zugreifen:"
echo "  kubectl -n $NAMESPACE port-forward svc/$VLLM_SERVICE_NAME 8000:8000   # vLLM API"
echo "  kubectl -n $NAMESPACE port-forward svc/$WEBUI_SERVICE_NAME 8080:8080  # Open WebUI"
echo -e "\nÖffnen Sie dann http://localhost:8080 in Ihrem Browser für die WebUI"
echo "Die vLLM API ist unter http://localhost:8000 erreichbar"

if [ "$CREATE_INGRESS" == "true" ]; then
    echo -e "\nIngress wird erstellt für: $DOMAIN_NAME"
    "$SCRIPT_DIR/scripts/create-ingress.sh"
    echo "Nach erfolgreichem Ingress-Setup können Sie Ihren Dienst unter https://$DOMAIN_NAME erreichen"
fi

echo -e "\nWenn Sie die GPU-Ressourcen skalieren möchten, verwenden Sie:"
echo "  ./scripts/scale-gpu.sh --count <1-4>  # Anzahl der GPUs anpassen"

echo -e "\nWeitere Informationen finden Sie in der DOCUMENTATION.md"
