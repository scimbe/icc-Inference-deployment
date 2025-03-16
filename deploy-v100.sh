#!/bin/bash
# ============================================================================
# LLM V100 Deployment Script
# ============================================================================
# Autor: HAW Hamburg ICC Team
# Version: 2.0.0
# 
# Dieses Skript startet TGI oder vLLM mit V100-spezifischen Optimierungen
# auf der ICC Kubernetes-Plattform.
# ============================================================================

set -eo pipefail

# ============================================================================
# Farbdefinitionen und Hilfsfunktionen
# ============================================================================

# Farbcodes für Ausgaben
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Ausgabefunktionen
function error() {
    echo -e "${RED}FEHLER: $1${NC}" >&2
    exit 1
}

function info() {
    echo -e "${BLUE}$1${NC}"
}

function success() {
    echo -e "${GREEN}$1${NC}"
}

function warn() {
    echo -e "${YELLOW}$1${NC}"
}

function header() {
    echo -e "\n${BOLD}${PURPLE}=== $1 ===${NC}"
}

# Eingabe mit Standardwert
function prompt_with_default() {
    local prompt="$1"
    local default="$2"
    
    echo -e -n "$prompt [${CYAN}$default${NC}]: "
    read -r input
    echo "${input:-$default}"
}

# Ja/Nein-Frage
function yes_no_prompt() {
    local prompt="$1"
    local default="${2:-n}"  # Default-Wert, standardmäßig "n"
    
    local options
    if [[ "$default" == "j" || "$default" == "J" || "$default" == "y" || "$default" == "Y" ]]; then
        options="[${CYAN}J${NC}/n]"
        default="j"
    else
        options="[j/${CYAN}N${NC}]"
        default="n"
    fi
    
    while true; do
        echo -e -n "$prompt $options: "
        read -r input
        input=${input:-$default}
        
        case "$input" in
            [jJyY]) return 0 ;;
            [nN]) return 1 ;;
            *) echo "Bitte antworten Sie mit 'j' oder 'n'." ;;
        esac
    done
}

# ============================================================================
# Überprüfung der Voraussetzungen
# ============================================================================

# Verzeichnise und Konfiguration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
CONFIG_FILE="$ROOT_DIR/configs/config.sh"

# Banner anzeigen
cat << "EOF"
  _____  ______   ______   _      _      __  __    ______           __                                  __ 
 |_   _|/ ___) | / ___) | | |    | |    |  \/  |  /_  __/__  ____  / /___  __  ___   _____  ____  _____/ /_
   | | | |   | || |   | | | |    | |    | |\/| |   / / / _ \/ __ \/ / __ \/ / / / | / / _ \/ __ \/ ___/ __/
   | | | |___| || |___| | | |___ | |___ | |  | |  / / /  __/ /_/ / / /_/ / /_/ /| |/ /  __/ / / / /  / /_  
   |_| \______|_|\____)_| |_____||_____||_|  |_|  /_/  \___/ .___/_/\____/\__, / |___/\___/_/ /_/_/   \__/  
                                                          /_/            /____/                       V100
EOF

echo -e "\n${BLUE}${BOLD}LLM Deployment System für NVIDIA Tesla V100 GPUs${NC}"
echo -e "HAW Hamburg Informatik Compute Cloud (ICC)\n"

# Prüfe, ob kubectl verfügbar ist
if ! command -v kubectl &> /dev/null; then
    error "kubectl ist nicht installiert. Bitte installieren Sie kubectl gemäß der Anleitung: https://kubernetes.io/docs/tasks/tools/"
fi

# Prüfe, ob Config-Datei existiert
if [ ! -f "$CONFIG_FILE" ]; then
    warn "Konfigurationsdatei nicht gefunden: $CONFIG_FILE"
    
    # Frage nach automatischem Kopieren
    if yes_no_prompt "Soll die V100-Beispielkonfiguration automatisch kopiert werden?"; then
        if [ -f "$ROOT_DIR/configs/config.v100.sh" ]; then
            cp "$ROOT_DIR/configs/config.v100.sh" "$CONFIG_FILE"
            success "Konfiguration wurde kopiert. Bitte passen Sie die Werte an."
            
            # Öffne die Datei zur Bearbeitung, wenn Editoren verfügbar sind
            if command -v nano &> /dev/null; then
                if yes_no_prompt "Möchten Sie die Konfigurationsdatei jetzt bearbeiten?"; then
                    nano "$CONFIG_FILE"
                fi
            fi
        else
            error "Die Beispielkonfiguration configs/config.v100.sh wurde nicht gefunden."
        fi
    else
        error "Bitte erstellen Sie die Konfigurationsdatei manuell mit: cp configs/config.v100.sh configs/config.sh"
    fi
fi

# Skripte ausführbar machen
header "Skript-Berechtigungen prüfen"
if [ ! -x "$ROOT_DIR/scripts/deploy-tgi-v100.sh" ] || [ ! -x "$ROOT_DIR/scripts/deploy-vllm-v100.sh" ]; then
    warn "Setze Ausführungsberechtigungen für Skripte..."
    chmod +x "$ROOT_DIR/scripts"/*.sh
    success "Berechtigungen gesetzt"
else
    info "Skript-Berechtigungen sind korrekt ✓"
fi

# ============================================================================
# Lade Konfiguration
# ============================================================================

header "Lade Konfiguration"
source "$CONFIG_FILE"

# Prüfe kritische Konfigurationsvariablen
[[ -z "$NAMESPACE" ]] && error "NAMESPACE ist nicht konfiguriert in config.sh"

# Standard-Engine bestimmen
ENGINE_TYPE="${ENGINE_TYPE:-tgi}"
if [[ "$ENGINE_TYPE" != "tgi" && "$ENGINE_TYPE" != "vllm" ]]; then
    warn "Ungültiger ENGINE_TYPE: $ENGINE_TYPE. Setze auf Standard-Engine 'tgi'"
    ENGINE_TYPE="tgi"
fi

# ============================================================================
# Deployment-Engine auswählen und starten
# ============================================================================

header "Deployment-Konfiguration"
echo -e "Namespace: ${CYAN}$NAMESPACE${NC}"
echo -e "Modell: ${CYAN}$MODEL_NAME${NC}"
echo -e "GPU-Konfiguration: ${CYAN}${GPU_COUNT}x ${GPU_TYPE}${NC}"
echo -e "Quantisierung: ${CYAN}${QUANTIZATION:-Keine (float16)}${NC}"
echo -e "Engine: ${CYAN}${ENGINE_TYPE}${NC}"

# Engine bestätigen oder ändern
if yes_no_prompt "Möchten Sie die Engine ändern?"; then
    # Engine-Auswahl
    echo -e "Verfügbare Engines:"
    echo -e "  1) ${CYAN}TGI${NC} (Text Generation Inference)"
    echo -e "  2) ${CYAN}vLLM${NC} (Very Large Language Model Inference)"
    
    while true; do
        echo -n "Wählen Sie die Engine (1/2): "
        read -r engine_choice
        
        case "$engine_choice" in
            1) ENGINE_TYPE="tgi"; break ;;
            2) ENGINE_TYPE="vllm"; break ;;
            *) echo "Ungültige Auswahl. Bitte 1 oder 2 eingeben." ;;
        esac
    done
fi

# Starte das entsprechende Deployment
header "Starte $ENGINE_TYPE Deployment"

case "$ENGINE_TYPE" in
    "tgi")
        info "Starte Text Generation Inference (TGI)..."
        "$ROOT_DIR/scripts/deploy-tgi-v100.sh"
        ;;
    "vllm")
        info "Starte vLLM..."
        "$ROOT_DIR/scripts/deploy-vllm-v100.sh"
        ;;
    *)
        error "Ungültiger ENGINE_TYPE: $ENGINE_TYPE"
        ;;
esac

# ============================================================================
# WebUI installieren
# ============================================================================

header "WebUI für $ENGINE_TYPE"

if yes_no_prompt "Möchten Sie die WebUI installieren?"; then
    info "Starte WebUI Installation..."
    "$ROOT_DIR/scripts/deploy-webui.sh"
    WEBUI_INSTALLED=true
else
    info "WebUI-Installation übersprungen."
    WEBUI_INSTALLED=false
fi

# ============================================================================
# Zusammenfassung und nächste Schritte
# ============================================================================

header "Deployment abgeschlossen"

# Zugriffsinformationen anzeigen
if [ "$WEBUI_INSTALLED" = true ]; then
    success "✅ LLM-Deployment mit WebUI erfolgreich"
    echo -e "\nFühren Sie das folgende Kommando aus, um auf die WebUI und API zuzugreifen:"
    echo -e "  ${CYAN}./scripts/port-forward.sh${NC}"
    echo -e "\nWebUI wird verfügbar sein unter: ${GREEN}http://localhost:3000${NC}"
    echo -e "API wird verfügbar sein unter: ${GREEN}http://localhost:8000${NC}"
else
    success "✅ LLM-Deployment ohne WebUI erfolgreich"
    echo -e "\nFür API-Zugriff können Sie Port-Forwarding einrichten mit:"
    if [ "$ENGINE_TYPE" = "tgi" ]; then
        echo -e "  ${CYAN}kubectl -n $NAMESPACE port-forward svc/$TGI_SERVICE_NAME 8000:8000${NC}"
    else
        echo -e "  ${CYAN}kubectl -n $NAMESPACE port-forward svc/$VLLM_SERVICE_NAME 8000:8000${NC}"
    fi
    echo -e "\nAPI wird verfügbar sein unter: ${GREEN}http://localhost:8000${NC}"
    
    # WebUI später installieren?
    echo -e "\nSie können die WebUI später installieren mit:"
    echo -e "  ${CYAN}./scripts/deploy-webui.sh${NC}"
fi

# Überwachungshinweise
echo -e "\n${PURPLE}Nützliche Befehle:${NC}"
echo -e "  ${CYAN}./scripts/monitor-gpu.sh${NC} - GPU-Auslastung in Echtzeit überwachen"
echo -e "  ${CYAN}./scripts/check-logs.sh tgi${NC} - Logs des LLM-Servers anzeigen"
echo -e "  ${CYAN}./scripts/test-gpu.sh${NC} - GPU-Funktionalität testen"
echo -e "\nWeitere Informationen finden Sie in ${CYAN}COMMANDS.md${NC}"

exit 0
