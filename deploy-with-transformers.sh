#!/bin/bash

# Hauptskript für das Deployment von Text Generation Inference (TGI) und Open WebUI mit Transformers
set -e

# Pfad zum Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Farben für bessere Lesbarkeit
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Prüfe, ob transformers-Config vorhanden ist, sonst erstelle sie
if [ ! -f "$SCRIPT_DIR/configs/config.sh" ]; then
    if [ -f "$SCRIPT_DIR/configs/config.transformers.sh" ]; then
        echo -e "${YELLOW}Keine config.sh gefunden. Verwende config.transformers.sh...${NC}"
        cp "$SCRIPT_DIR/configs/config.transformers.sh" "$SCRIPT_DIR/configs/config.sh"
    else
        echo -e "${YELLOW}Keine config.sh gefunden. Erstelle Standardkonfiguration...${NC}"
        cp "$SCRIPT_DIR/configs/config.example.sh" "$SCRIPT_DIR/configs/config.sh"
        
        # Aktiviere Transformers in der neuen Konfiguration
        echo -e "\n# Transformers-Konfiguration" >> "$SCRIPT_DIR/configs/config.sh"
        echo "export ENABLE_TRANSFORMERS=true" >> "$SCRIPT_DIR/configs/config.sh"
        echo "export TRUST_REMOTE_CODE=true" >> "$SCRIPT_DIR/configs/config.sh"
        echo "export TOKENIZERS_PARALLELISM=true" >> "$SCRIPT_DIR/configs/config.sh"
        echo "export TRANSFORMERS_CACHE=\"/data/transformers-cache\"" >> "$SCRIPT_DIR/configs/config.sh"
        echo "export MAX_BATCH_SIZE=8" >> "$SCRIPT_DIR/configs/config.sh"
    fi
    
    echo -e "${GREEN}Bitte überprüfen und anpassen Sie die Konfiguration in configs/config.sh${NC}"
    echo "Insbesondere den Namespace und ggf. das Hugging Face Token für geschützte Modelle."
    read -p "Drücken Sie Enter, um fortzufahren oder Ctrl+C zum Abbrechen..."
fi

# Lade Konfiguration
source "$SCRIPT_DIR/configs/config.sh"

# Prüfe, ob kubectl verfügbar ist
if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}Fehler: kubectl ist nicht installiert oder nicht im PATH.${NC}"
    echo -e "Bitte installieren Sie kubectl gemäß der Anleitung: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Prüfe, ob Namespace existiert
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo -e "${YELLOW}Fehler: Namespace $NAMESPACE existiert nicht.${NC}"
    echo -e "Bitte überprüfen Sie Ihre Konfiguration und stellen Sie sicher, dass Sie bei der ICC eingeloggt sind."
    echo -e "Sie können sich mit dem Skript ./scripts/icc-login.sh anmelden."
    exit 1
fi

echo -e "${BLUE}=== ICC TGI Deployment mit Transformers-Integration ===${NC}"
echo -e "Namespace: $NAMESPACE"
echo -e "GPU-Unterstützung: $([ "$USE_GPU" == "true" ] && echo "Aktiviert ($GPU_TYPE, $GPU_COUNT GPU(s))" || echo "Deaktiviert")"
echo -e "Modell: $MODEL_NAME"
echo -e "Transformers: $([ "${ENABLE_TRANSFORMERS:-false}" == "true" ] && echo "Aktiviert" || echo "Deaktiviert")"

# Setze Berechtigungen für Skripte
chmod +x "$SCRIPT_DIR/scripts/deploy-tgi-transformers.sh"
chmod +x "$SCRIPT_DIR/scripts/deploy-webui-transformers.sh"

# Führe Deployment-Skripte aus
echo -e "\n${BLUE}1. Deploying Text Generation Inference mit Transformers...${NC}"
"$SCRIPT_DIR/scripts/deploy-tgi-transformers.sh"

echo -e "\n${BLUE}2. Deploying Open WebUI mit Transformers-Unterstützung...${NC}"
"$SCRIPT_DIR/scripts/deploy-webui-transformers.sh"

echo -e "\n${GREEN}=== Deployment abgeschlossen! ===${NC}"
echo -e "Überprüfen Sie den Status mit: kubectl -n $NAMESPACE get pods"

# Zeige Anweisungen für den Zugriff
echo -e "\n${BLUE}=== Zugriff auf die Dienste ===${NC}"
echo -e "Hinweis: TGI muss das Modell beim ersten Start herunterladen, was einige Zeit dauern kann."
echo -e "Überwachen Sie den Fortschritt mit: kubectl -n $NAMESPACE logs -f deployment/$TGI_DEPLOYMENT_NAME"
echo
echo -e "Um auf TGI und die WebUI zuzugreifen, führen Sie aus:"
echo -e "  ${GREEN}./scripts/port-forward.sh${NC}"
echo
echo -e "Alternativ können Sie auf die einzelnen Dienste separat zugreifen:"
echo -e "  kubectl -n $NAMESPACE port-forward svc/$TGI_SERVICE_NAME 8000:8000   # TGI API"
echo -e "  kubectl -n $NAMESPACE port-forward svc/$WEBUI_SERVICE_NAME 3000:3000  # Open WebUI"
echo -e "\nÖffnen Sie dann http://localhost:3000 in Ihrem Browser für die WebUI"
echo -e "Die TGI API ist unter http://localhost:8000 erreichbar"

if [ "$CREATE_INGRESS" == "true" ]; then
    echo -e "\nIngress wird erstellt für: $DOMAIN_NAME"
    "$SCRIPT_DIR/scripts/create-ingress.sh"
    echo -e "Nach erfolgreichem Ingress-Setup können Sie Ihren Dienst unter https://$DOMAIN_NAME erreichen"
fi

echo -e "\n${BLUE}=== Transformers-Integration ===${NC}"
echo -e "Die WebUI ist mit erweiterten transformers-Funktionen konfiguriert:"
echo -e "  - Direkter Zugriff auf HuggingFace-Modelle"
echo -e "  - Erweiterte Modellkonfiguration über die WebUI-Einstellungen"
echo -e "  - Parameter wie Temperatur, Top-k, Top-p und Sampling konfigurierbar"
echo -e "  - Modellkontextverwaltung mit konfigurierbarer Kontextlänge"

echo -e "\n${BLUE}=== Weitere Schritte ===${NC}"
echo -e "Wenn Sie die GPU-Ressourcen skalieren möchten, verwenden Sie:"
echo -e "  ${GREEN}./scripts/scale-gpu.sh --count <1-4>${NC}  # Anzahl der GPUs anpassen"

echo -e "\nWeitere Informationen finden Sie in der DOCUMENTATION.md"
