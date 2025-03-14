#!/bin/bash

# Skript zum Öffnen der ICC-Login-Seite und Hilfe beim Download der Kubeconfig
set -e

# Farbdefinitionen
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ICC_LOGIN_URL="https://icc-login.informatik.haw-hamburg.de/"
KUBECONFIG_PATH="$HOME/.kube/config"   # Standard-Kubeconfig-Pfad

echo -e "${BLUE}=== ICC Login Helper ===${NC}"
echo -e "Dieses Skript öffnet die ICC-Login-Seite in Ihrem Standard-Browser."
echo -e "Sie können dann:"
echo -e "  1. Sich mit Ihrer ${YELLOW}infw-Kennung${NC} anmelden"
echo -e "  2. Die Kubeconfig-Datei herunterladen"
echo -e "  3. Die Datei in Ihrem Kubernetes-Konfigurationsverzeichnis platzieren"
echo

# Funktion zum Öffnen des Browsers basierend auf dem Betriebssystem
open_browser() {
    case "$(uname -s)" in
        Linux*)
            if command -v xdg-open &> /dev/null; then
                xdg-open "$ICC_LOGIN_URL"
            else
                echo -e "${YELLOW}Konnte den Browser nicht automatisch öffnen.${NC}"
                echo -e "Bitte öffnen Sie manuell die URL: $ICC_LOGIN_URL"
                return 1
            fi
            ;;
        Darwin*)  # macOS
            open "$ICC_LOGIN_URL"
            ;;
        CYGWIN*|MINGW*|MSYS*)  # Windows
            start "$ICC_LOGIN_URL" || (
                echo -e "${YELLOW}Konnte den Browser nicht automatisch öffnen.${NC}"
                echo -e "Bitte öffnen Sie manuell die URL: $ICC_LOGIN_URL"
                return 1
            )
            ;;
        *)
            echo -e "${YELLOW}Unbekanntes Betriebssystem. Konnte den Browser nicht automatisch öffnen.${NC}"
            echo -e "Bitte öffnen Sie manuell die URL: $ICC_LOGIN_URL"
            return 1
            ;;
    esac
    return 0
}

# Öffne Browser
echo -e "Öffne Browser mit der ICC-Login-Seite..."
if open_browser; then
    echo -e "${GREEN}✓${NC} Browser wurde geöffnet."
else
    echo -e "Bitte öffnen Sie die Seite manuell: $ICC_LOGIN_URL"
fi

echo
echo -e "${BLUE}=== Anleitung ===${NC}"
echo -e "1. Melden Sie sich mit Ihrer infw-Kennung an."
echo -e "2. Klicken Sie auf 'Download Config'."
echo -e "3. Warten Sie, bis die Konfigurationsdatei heruntergeladen wurde."
echo

# Warte auf Benutzereingabe, um fortzufahren
read -p "Drücken Sie Enter, wenn Sie die Konfigurationsdatei heruntergeladen haben..." -r

# Frage nach dem Pfad zur heruntergeladenen Datei
echo
echo -e "${BLUE}=== Kubeconfig einrichten ===${NC}"
echo -e "Bitte geben Sie den vollständigen Pfad zur heruntergeladenen Konfigurationsdatei an"
echo -e "(oder lassen Sie es leer, um den Standardpfad zu verwenden: ~/Downloads/config.txt):"
read -r CONFIG_PATH

# Wenn kein Pfad angegeben wurde, verwende Standardpfad
if [ -z "$CONFIG_PATH" ]; then
    CONFIG_PATH="$HOME/Downloads/config.txt"
    echo -e "Verwende Standardpfad: $CONFIG_PATH"
fi

# Überprüfe, ob die Datei existiert
if [ ! -f "$CONFIG_PATH" ]; then
    echo -e "${YELLOW}Die angegebene Datei wurde nicht gefunden: $CONFIG_PATH${NC}"
    echo -e "Bitte geben Sie den korrekten Pfad zur heruntergeladenen Konfigurationsdatei an:"
    read -r CONFIG_PATH
    
    if [ ! -f "$CONFIG_PATH" ]; then
        echo -e "${YELLOW}Die Datei wurde erneut nicht gefunden. Breche ab.${NC}"
        exit 1
    fi
fi

# Erstelle .kube-Verzeichnis, falls es nicht existiert
mkdir -p "$HOME/.kube"

# Kopiere die Konfigurationsdatei
echo -e "Kopiere Konfigurationsdatei nach $KUBECONFIG_PATH..."
cp "$CONFIG_PATH" "$KUBECONFIG_PATH"

# Setze Berechtigungen
chmod 600 "$KUBECONFIG_PATH"

echo -e "${GREEN}✓${NC} Kubeconfig wurde erfolgreich eingerichtet!"
echo -e "Sie können jetzt kubectl verwenden, um mit der ICC zu interagieren."
echo

# Teste die Verbindung
echo -e "${BLUE}=== Verbindungstest ===${NC}"
echo -e "Teste Verbindung zur ICC..."
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✓${NC} Verbindung erfolgreich hergestellt!"
    echo -e "Ihre aktueller Kontext ist: $(kubectl config current-context)"
    
    # Hole Namespace-Information basierend auf der w-Kennung
    CURRENT_CONTEXT=$(kubectl config current-context)
    CURRENT_NS=$(kubectl config view --minify -o jsonpath='{..namespace}')
    
    echo -e "\n${BLUE}=== Namespace-Informationen ===${NC}"
    if [ -z "$CURRENT_NS" ]; then
        echo -e "${YELLOW}Kein Namespace in der Kubeconfig definiert.${NC}"
        
        # Versuche, die W-Kennung aus dem Kontext zu extrahieren
        if [[ "$CURRENT_CONTEXT" =~ w[a-z0-9]+ ]]; then
            W_KENNUNG=${BASH_REMATCH[0]}
            SUGGESTED_NS="${W_KENNUNG}-default"
            echo -e "Basierend auf Ihrem Kontext könnte Ihr Namespace ${YELLOW}$SUGGESTED_NS${NC} sein."
            
            read -p "Möchten Sie diesen Namespace verwenden? (j/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Jj]$ ]]; then
                # Setze den Namespace
                kubectl config set-context --current --namespace="$SUGGESTED_NS"
                echo -e "${GREEN}✓${NC} Namespace wurde auf $SUGGESTED_NS gesetzt."
                CURRENT_NS="$SUGGESTED_NS"
            else
                echo -e "Bitte geben Sie Ihren Namespace manuell an:"
                read -r MANUAL_NS
                if [ -n "$MANUAL_NS" ]; then
                    kubectl config set-context --current --namespace="$MANUAL_NS"
                    echo -e "${GREEN}✓${NC} Namespace wurde auf $MANUAL_NS gesetzt."
                    CURRENT_NS="$MANUAL_NS"
                fi
            fi
        else
            echo -e "Konnte keine W-Kennung aus dem Kontext ableiten."
            echo -e "Bitte geben Sie Ihren Namespace manuell an (Format: wXXXXX-default):"
            read -r MANUAL_NS
            if [ -n "$MANUAL_NS" ]; then
                kubectl config set-context --current --namespace="$MANUAL_NS"
                echo -e "${GREEN}✓${NC} Namespace wurde auf $MANUAL_NS gesetzt."
                CURRENT_NS="$MANUAL_NS"
            fi
        fi
    else
        echo -e "Ihr aktueller Namespace ist: ${YELLOW}$CURRENT_NS${NC}"
    fi
    
    # Prüfe Zugriff auf den Namespace
    if [ -n "$CURRENT_NS" ]; then
        if kubectl get namespace "$CURRENT_NS" &> /dev/null; then
            echo -e "${GREEN}✓${NC} Zugriff auf Namespace $CURRENT_NS bestätigt."
            
            # Prüfe auf vorhandene Deployments
            echo -e "\n${BLUE}=== Bestehende Deployments ===${NC}"
            DEPLOYMENTS=$(kubectl get deployments 2>/dev/null)
            if [ -n "$DEPLOYMENTS" ]; then
                echo -e "Sie haben bereits Deployments in Ihrem Namespace:"
                echo "$DEPLOYMENTS"
                echo -e "\nFalls Sie ein neues vLLM-Deployment erstellen möchten, stellen Sie sicher,"
                echo -e "dass die Deployment-Namen in der config.sh nicht kollidieren."
            else
                echo -e "Keine bestehenden Deployments gefunden. Bereit für ein neues vLLM-Deployment."
            fi
            
            # Prüfe auf verfügbare GPU-Ressourcen
            echo -e "\n${BLUE}=== Verfügbare GPU-Ressourcen ===${NC}"
            # Prüfe, ob gpu-Klasse vorhanden ist
            if kubectl get nodes -o json | grep -q '"nvidia.com/gpu":'; then
                echo -e "${GREEN}✓${NC} GPUs sind im Cluster verfügbar."
                
                # Zeige verfügbare GPU-Kapazität
                GPU_NODES=$(kubectl get nodes -o=custom-columns=NODE:.metadata.name,GPU:.status.capacity.'nvidia\.com/gpu' | grep -v "<none>")
                if [ -n "$GPU_NODES" ]; then
                    echo -e "GPU-Nodes im Cluster:"
                    echo "$GPU_NODES"
                else
                    echo -e "${YELLOW}Keine Nodes mit GPUs gefunden. Bitte überprüfen Sie die Cluster-Konfiguration.${NC}"
                fi
            else
                echo -e "${YELLOW}Keine GPU-Ressourcen im Cluster verfügbar.${NC}"
                echo -e "Falls Sie GPUs benötigen, wenden Sie sich an den ICC-Administrator."
            fi
        else
            echo -e "${YELLOW}Zugriff auf Namespace $CURRENT_NS fehlgeschlagen.${NC}"
            echo -e "Möglicherweise haben Sie keine Berechtigungen für diesen Namespace."
        fi
    fi
else
    echo -e "${YELLOW}Verbindung zur ICC konnte nicht hergestellt werden.${NC}"
    echo -e "Bitte überprüfen Sie Ihre VPN-Verbindung und die Kubeconfig-Datei."
fi

echo
echo -e "${GREEN}=== Konfiguration für vLLM-Deployment ===${NC}"
echo -e "Erstellen Sie nun eine Konfigurationsdatei mit dem korrekten Namespace:"
echo -e "cp configs/config.example.sh configs/config.sh"
echo -e "vim configs/config.sh  # Namespace: $CURRENT_NS"
echo
echo -e "Anschließend können Sie das Deployment starten mit:"
echo -e "./deploy.sh"
