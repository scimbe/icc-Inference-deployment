#!/bin/bash

# GPU-Monitoring-Skript für TGI/vLLM in Kubernetes mit TUI (Terminal User Interface)
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

# Farbdefinitionen
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Hilfsfunktion: Zeige Hilfe an
show_help() {
    echo "Verwendung: $0 [OPTIONEN]"
    echo
    echo "GPU-Monitoring mit TUI (Terminal User Interface) für TGI/vLLM in Kubernetes"
    echo
    echo "Optionen:"
    echo "  -h, --help        Diese Hilfe anzeigen"
    echo "  -i, --interval    Aktualisierungsintervall in Sekunden (Standard: 2)"
    echo "  -f, --format      Ausgabeformat: 'full' oder 'compact' (Standard: compact)"
    echo "  -s, --save        Daten in CSV-Datei speichern (Dateiname als Argument)"
    echo "  -c, --count       Anzahl der Messungen (Standard: kontinuierlich)"
    echo
    echo "Beispiele:"
    echo "  $0                             # Standard-Monitoring mit TUI"
    echo "  $0 -i 5                        # 5-Sekunden-Aktualisierungsintervall"
    echo "  $0 -f full                     # Ausführlichere Anzeige"
    echo "  $0 -s gpu_metrics.csv          # Speichere parallel im CSV-Format"
    echo "  $0 -c 10                       # Führe 10 Messungen durch und beende"
    exit 0
}

# Standardwerte
INTERVAL=2
FORMAT="compact"
SAVE_FILE=""
COUNT=0  # 0 bedeutet kontinuierlich

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -i|--interval)
            INTERVAL="$2"
            shift 2
            ;;
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        -s|--save)
            SAVE_FILE="$2"
            shift 2
            ;;
        -c|--count)
            COUNT="$2"
            shift 2
            ;;
        *)
            echo "Unbekannte Option: $1"
            show_help
            ;;
    esac
done

# Überprüfe, ob notwendige Befehle verfügbar sind
if ! command -v tput &> /dev/null; then
    echo "Warnung: 'tput' ist nicht installiert. Einige Formatierungsfunktionen könnten eingeschränkt sein."
    # Füge grundlegende tput-Funktionen hinzu, falls nicht vorhanden
    tput() {
        case "$1" in
            cup)
                echo -e "\033[${2};${3}H"
                ;;
            smcup|rmcup)
                # Nichts tun, wenn nicht unterstützt
                ;;
            *)
                # Für andere Befehle nichts tun
                ;;
        esac
    }
fi

# Erkenne den Deployment-Typ und -Namen
DEPLOYMENT_NAME=""
DEPLOYMENT_TYPE=""
SERVICE_NAME=""
POD_LABEL=""

# Prüfe TGI Deployment
if kubectl -n "$NAMESPACE" get deployment "${TGI_DEPLOYMENT_NAME:-inf-server}" &> /dev/null; then
    DEPLOYMENT_NAME="${TGI_DEPLOYMENT_NAME:-inf-server}"
    SERVICE_NAME="${TGI_SERVICE_NAME:-inf-service}"
    DEPLOYMENT_TYPE="TGI"
    POD_LABEL="app=llm-server"
# Prüfe vLLM Deployment
elif kubectl -n "$NAMESPACE" get deployment "${VLLM_DEPLOYMENT_NAME:-vllm-server}" &> /dev/null; then
    DEPLOYMENT_NAME="${VLLM_DEPLOYMENT_NAME:-vllm-server}"
    SERVICE_NAME="${VLLM_SERVICE_NAME:-vllm-service}"
    DEPLOYMENT_TYPE="vLLM"
    POD_LABEL="service=vllm-server"
else
    echo "Fehler: Weder TGI (${TGI_DEPLOYMENT_NAME:-inf-server}) noch vLLM (${VLLM_DEPLOYMENT_NAME:-vllm-server}) Deployment gefunden."
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

echo "Erkanntes Deployment: $DEPLOYMENT_TYPE ($DEPLOYMENT_NAME)"

# Hole den Pod-Namen
POD_NAME=$(kubectl -n "$NAMESPACE" get pod -l "$POD_LABEL" -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD_NAME" ]; then
    echo "Fehler: Konnte keinen laufenden $DEPLOYMENT_TYPE Pod finden."
    exit 1
fi

# Überprüfe, ob nvidia-smi im Pod verfügbar ist
if ! kubectl -n "$NAMESPACE" exec "$POD_NAME" -- which nvidia-smi &> /dev/null; then
    echo "Fehler: nvidia-smi ist im Pod nicht verfügbar. Ist GPU aktiviert?"
    exit 1
fi

# CSV-Header initialisieren, falls erforderlich
if [ -n "$SAVE_FILE" ]; then
    echo "Zeitstempel,GPU-Index,GPU-Name,Temperatur,GPU-Auslastung,Speicher-Auslastung,Verwendeter Speicher,Freier Speicher,LLM-Prozesse" > "$SAVE_FILE"
    echo "CSV-Ausgabe wird in '$SAVE_FILE' gespeichert."
fi

# Temporäre Datei für die Ausgabe
TMP_OUTPUT=$(mktemp)
trap 'rm -f "$TMP_OUTPUT"' EXIT

# Monitoring-Funktion für volle Ausgabe
monitor_full() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Header
    echo -e "${BOLD}=== GPU-Monitoring ($timestamp) ===${NC}"
    echo -e "${BLUE}Pod:${NC} $POD_NAME"
    echo -e "${BLUE}Namespace:${NC} $NAMESPACE"
    echo -e "${BLUE}Modell:${NC} $MODEL_NAME"
    echo -e "${BLUE}Engine:${NC} $DEPLOYMENT_TYPE"
    echo
    
    # GPU-Informationen
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi
    
    echo -e "\n${BOLD}--- LLM Prozesse ---${NC}"
    if [ "$DEPLOYMENT_TYPE" = "TGI" ]; then
        kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ps aux | grep -E "python|text-generation|cuda" | grep -v grep || echo "Keine LLM-Prozesse gefunden"
    else
        kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ps aux | grep -E "python|vllm|api_server|cuda" | grep -v grep || echo "Keine LLM-Prozesse gefunden"
    fi
    
    # GPU-Metriken erfassen für CSV
    if [ -n "$SAVE_FILE" ]; then
        kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.free --format=csv,noheader | while read -r line; do
            # Zähle LLM Prozesse
            if [ "$DEPLOYMENT_TYPE" = "TGI" ]; then
                LLM_PROCS=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ps aux | grep -c -E "python|text-generation" || echo "0")
            else
                LLM_PROCS=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ps aux | grep -c -E "python|vllm|api_server" || echo "0")
            fi
            echo "$timestamp,$line,$LLM_PROCS" >> "$SAVE_FILE"
        done
    fi
    
    # API-Status prüfen
    echo -e "\n${BOLD}--- LLM API Status ---${NC}"
    # Temporäres Port-Forwarding
    PF_PORT=9999
    kubectl -n "$NAMESPACE" port-forward svc/"$SERVICE_NAME" ${PF_PORT}:8000 &>/dev/null &
    PF_PID=$!
    # Warte kurz und teste API
    sleep 2
    if curl -s localhost:${PF_PORT}/v1/models &>/dev/null; then
        API_RESPONSE=$(curl -s localhost:${PF_PORT}/v1/models)
        echo -e "${GREEN}API ist verfügbar${NC}"
        MODEL_ID=$(echo "$API_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"//g')
        if [ -n "$MODEL_ID" ]; then
            echo -e "  Geladenes Modell: $MODEL_ID"
        else
            echo -e "  Modell wird geladen oder ID nicht erkannt"
        fi
    else
        echo -e "${RED}API ist nicht erreichbar${NC}"
    fi
    # Beende Port-Forwarding
    kill $PF_PID &>/dev/null || true
}

# Monitoring-Funktion für kompakte Ausgabe
monitor_compact() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Header
    echo -e "${BOLD}=== GPU-Monitoring ($timestamp) ===${NC}"
    echo -e "${BLUE}Pod:${NC} $POD_NAME"
    echo -e "${BLUE}Namespace:${NC} $NAMESPACE"
    echo -e "${BLUE}Modell:${NC} $MODEL_NAME"
    echo -e "${BLUE}Engine:${NC} $DEPLOYMENT_TYPE"
    echo
    
    # GPU-Informationen in kompaktem Format
    echo -e "${BOLD}GPU-Status:${NC}"
    kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.free --format=csv
    
    # GPU-Metriken erfassen für CSV
    if [ -n "$SAVE_FILE" ]; then
        kubectl -n "$NAMESPACE" exec "$POD_NAME" -- nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.free --format=csv,noheader | while read -r line; do
            # Zähle LLM Prozesse
            if [ "$DEPLOYMENT_TYPE" = "TGI" ]; then
                LLM_PROCS=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ps aux | grep -c -E "python|text-generation" || echo "0")
            else
                LLM_PROCS=$(kubectl -n "$NAMESPACE" exec "$POD_NAME" -- ps aux | grep -c -E "python|vllm|api_server" || echo "0")
            fi
            echo "$timestamp,$line,$LLM_PROCS" >> "$SAVE_FILE"
        done
    fi
    
    # Speicher und CPU-Auslastung des Pods
    echo -e "\n${BOLD}Pod-Ressourcen:${NC}"
    kubectl -n "$NAMESPACE" top pod "$POD_NAME" 2>/dev/null || echo "Ressourcennutzung nicht verfügbar (metrics-server erforderlich)"
}

# Hauptmonitoring-Funktion
run_monitoring() {
    case "$FORMAT" in
        "full")
            monitor_full > "$TMP_OUTPUT"
            ;;
        "compact"|*)
            monitor_compact > "$TMP_OUTPUT"
            ;;
    esac
    cat "$TMP_OUTPUT"
}

# TUI-Fallback für Systeme ohne 'watch'
run_tui_fallback() {
    echo "Starte GPU-Monitoring für Pod '$POD_NAME'..."
    echo "Intervall: $INTERVAL Sekunden"
    echo "Format: $FORMAT"
    if [ "$COUNT" -gt 0 ]; then
        echo "Anzahl der Messungen: $COUNT"
    else
        echo "Kontinuierliche Überwachung (CTRL+C zum Beenden)"
    fi
    echo
    
    # Zähler für die Messungen
    local mcount=0
    
    # Kontinuierliche Schleife mit verbesserter Bildschirmaktualisierung
    # Wir vermeiden "clear", da es zu Flackern führen kann
    while true; do
        # Cursor an den Anfang des Terminals bewegen
        tput cup 0 0
        
        # Ausgabe erzeugen
        run_monitoring
        
        # Zähle Messung
        mcount=$((mcount + 1))
        
        # Prüfe, ob die gewünschte Anzahl erreicht ist
        if [ "$COUNT" -gt 0 ] && [ "$mcount" -ge "$COUNT" ]; then
            echo "Monitoring abgeschlossen ($COUNT Messungen)"
            break
        fi
        
        # Warte auf das nächste Update
        sleep "$INTERVAL"
    done
}

# Hauptfunktion
main() {
    # Terminal vorbereiten
    clear
    
    echo "Starte GPU-Monitoring für Pod '$POD_NAME'..."
    echo "Intervall: $INTERVAL Sekunden"
    echo "Format: $FORMAT"
    if [ "$COUNT" -gt 0 ]; then
        echo "Anzahl der Messungen: $COUNT"
    else
        echo "Kontinuierliche Überwachung (CTRL+C zum Beenden)"
    fi
    
    # Verzögerung, damit die Startmeldung sichtbar ist
    sleep 1
    
    # Bildschirm speichern, um später wieder dorthin zurückzukehren
    tput smcup
    
    # Auf CTRL+C reagieren, um Terminal ordnungsgemäß wiederherzustellen
    trap 'tput rmcup; echo "GPU-Monitoring beendet."; exit 0' SIGINT SIGTERM
    
    if command -v watch &> /dev/null && [[ "$OSTYPE" != "darwin"* ]]; then
        # Verwende 'watch' für bessere TUI, aber nur auf Linux (auf macOS verursacht watch oft Probleme)
        # Erstelle ein Skript, das 'run_monitoring' aufruft
        TMP_SCRIPT=$(mktemp)
        cat << EOF > "$TMP_SCRIPT"
#!/bin/bash
source "$ROOT_DIR/configs/config.sh"
$(declare -f monitor_full)
$(declare -f monitor_compact)
$(declare -f run_monitoring)
FORMAT="$FORMAT"
NAMESPACE="$NAMESPACE"
POD_NAME="$POD_NAME"
SAVE_FILE="$SAVE_FILE"
MODEL_NAME="$MODEL_NAME"
DEPLOYMENT_TYPE="$DEPLOYMENT_TYPE"
SERVICE_NAME="$SERVICE_NAME"
run_monitoring
EOF
        chmod +x "$TMP_SCRIPT"
        
        # Starte watch mit dem temporären Skript
        if [ "$COUNT" -gt 0 ]; then
            # Eine bestimmte Anzahl an Wiederholungen
            for (( i=1; i<=$COUNT; i++ )); do
                clear
                echo "Messung $i von $COUNT:"
                $TMP_SCRIPT
                if [ $i -lt $COUNT ]; then
                    sleep "$INTERVAL"
                fi
            done
        else
            # Kontinuierliche Überwachung
            watch --color -n "$INTERVAL" "$TMP_SCRIPT"
        fi
        
        # Aufräumen
        rm -f "$TMP_SCRIPT"
    else
        # Eigene Implementierung für macOS und für Systeme ohne 'watch'
        run_tui_fallback
    fi
    
    # Terminal wiederherstellen
    tput rmcup
}

# Starte das Monitoring
main