#!/bin/bash

# Skript zum Anzeigen und Analysieren von Logs der vLLM und WebUI Pods
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
    echo "Verwendung: $0 [OPTIONEN] [KOMPONENTE]"
    echo
    echo "Anzeigen und Analysieren von Logs der vLLM und WebUI Pods."
    echo
    echo "Optionen:"
    echo "  -h, --help        Diese Hilfe anzeigen"
    echo "  -f, --follow      Logs kontinuierlich anzeigen (wie 'tail -f')"
    echo "  -l, --lines NUM   Anzahl der anzuzeigenden Zeilen (Standard: 50)"
    echo "  -s, --save FILE   Logs in Datei speichern"
    echo "  -a, --analyze     Logs analysieren und Zusammenfassung anzeigen"
    echo
    echo "KOMPONENTE kann 'vllm', 'webui' oder 'all' sein (Standard: vllm)"
    echo
    echo "Beispiele:"
    echo "  $0                   # Zeigt die letzten 50 Zeilen der vLLM-Logs an"
    echo "  $0 webui -f          # Zeigt WebUI-Logs kontinuierlich an"
    echo "  $0 all -l 100        # Zeigt jeweils 100 Zeilen beider Komponenten an"
    echo "  $0 vllm -s logs.txt  # Speichert vLLM-Logs in logs.txt"
    echo "  $0 all -a            # Analysiert Logs beider Komponenten"
    exit 0
}

# Standardwerte
FOLLOW=false
LINES=50
SAVE_FILE=""
ANALYZE=false
COMPONENT="vllm"  # Standard-Komponente

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -f|--follow)
            FOLLOW=true
            shift
            ;;
        -l|--lines)
            LINES="$2"
            shift 2
            ;;
        -s|--save)
            SAVE_FILE="$2"
            shift 2
            ;;
        -a|--analyze)
            ANALYZE=true
            shift
            ;;
        vllm|webui|all)
            COMPONENT="$1"
            shift
            ;;
        *)
            echo "Unbekannte Option: $1"
            show_help
            ;;
    esac
done

# Überprüfe, ob die Deployments existieren
if ! kubectl -n "$NAMESPACE" get deployment "$VLLM_DEPLOYMENT_NAME" &> /dev/null; then
    echo -e "${RED}Fehler: vLLM Deployment '$VLLM_DEPLOYMENT_NAME' nicht gefunden.${NC}"
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

if ! kubectl -n "$NAMESPACE" get deployment "$WEBUI_DEPLOYMENT_NAME" &> /dev/null && [ "$COMPONENT" != "vllm" ]; then
    echo -e "${YELLOW}Warnung: WebUI Deployment '$WEBUI_DEPLOYMENT_NAME' nicht gefunden.${NC}"
    if [ "$COMPONENT" == "all" ]; then
        echo "Es werden nur vLLM-Logs angezeigt."
        COMPONENT="vllm"
    elif [ "$COMPONENT" == "webui" ]; then
        echo "Bitte führen Sie zuerst deploy.sh aus oder wählen Sie eine andere Komponente."
        exit 1
    fi
fi

# Funktion zum Anzeigen von Logs
show_logs() {
    local component=$1
    local deployment_name
    local pod_name
    
    if [ "$component" == "vllm" ]; then
        deployment_name="$VLLM_DEPLOYMENT_NAME"
    else
        deployment_name="$WEBUI_DEPLOYMENT_NAME"
    fi
    
    # Hole den neuesten Pod
    pod_name=$(kubectl -n "$NAMESPACE" get pod -l "service=$component" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$pod_name" ]; then
        echo -e "${RED}Fehler: Kein Pod für $component gefunden.${NC}"
        return 1
    fi
    
    echo -e "${BLUE}=== Logs für $component (Pod: $pod_name) ===${NC}"
    
    # Logs anzeigen oder speichern
    if [ "$FOLLOW" = true ]; then
        if [ -n "$SAVE_FILE" ]; then
            kubectl -n "$NAMESPACE" logs -f "$pod_name" | tee "$SAVE_FILE"
        else
            kubectl -n "$NAMESPACE" logs -f "$pod_name"
        fi
    else
        if [ -n "$SAVE_FILE" ]; then
            kubectl -n "$NAMESPACE" logs --tail="$LINES" "$pod_name" | tee "$SAVE_FILE"
        else
            kubectl -n "$NAMESPACE" logs --tail="$LINES" "$pod_name"
        fi
    fi
    
    return 0
}

# Funktion zur Log-Analyse
analyze_logs() {
    local component=$1
    local deployment_name
    local pod_name
    
    if [ "$component" == "vllm" ]; then
        deployment_name="$VLLM_DEPLOYMENT_NAME"
    else
        deployment_name="$WEBUI_DEPLOYMENT_NAME"
    fi
    
    # Hole den neuesten Pod
    pod_name=$(kubectl -n "$NAMESPACE" get pod -l "service=$component" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$pod_name" ]; then
        echo -e "${RED}Fehler: Kein Pod für $component gefunden.${NC}"
        return 1
    fi
    
    echo -e "${BLUE}=== Log-Analyse für $component (Pod: $pod_name) ===${NC}"
    
    # Temporäre Datei für Logs
    local temp_log_file=$(mktemp)
    kubectl -n "$NAMESPACE" logs "$pod_name" > "$temp_log_file"
    
    # Pod-Status und Restarts
    local pod_status=$(kubectl -n "$NAMESPACE" get pod "$pod_name" -o jsonpath='{.status.phase}')
    local restarts=$(kubectl -n "$NAMESPACE" get pod "$pod_name" -o jsonpath='{.status.containerStatuses[0].restartCount}')
    
    echo -e "Pod-Status: ${YELLOW}$pod_status${NC}"
    echo -e "Neustarts: ${YELLOW}$restarts${NC}"
    
    # Suche nach Fehlern und Warnungen
    local error_count=$(grep -c -i "error\|exception\|fail" "$temp_log_file")
    local warning_count=$(grep -c -i "warn\|warning" "$temp_log_file")
    
    echo -e "Fehler gefunden: ${RED}$error_count${NC}"
    echo -e "Warnungen gefunden: ${YELLOW}$warning_count${NC}"
    
    # Spezifische Analyse je nach Komponente
    if [ "$component" == "vllm" ]; then
        # Modell-Loading
        if grep -q "Loading model" "$temp_log_file"; then
            echo -e "${GREEN}✓${NC} Modell-Loading wurde gestartet"
            
            # Prüfe, ob das Modell geladen wurde
            if grep -q "Loading model weights" "$temp_log_file" && grep -q "Loaded model weights" "$temp_log_file"; then
                echo -e "${GREEN}✓${NC} Modell-Gewichte wurden geladen"
            else
                echo -e "${YELLOW}⚠${NC} Modell-Gewichte werden möglicherweise noch geladen"
            fi
            
            # Prüfe, ob der Server gestartet ist
            if grep -q "Running on http" "$temp_log_file"; then
                echo -e "${GREEN}✓${NC} Server läuft und akzeptiert Anfragen"
            else
                echo -e "${YELLOW}⚠${NC} Server wurde noch nicht vollständig gestartet"
            fi
        else
            echo -e "${YELLOW}⚠${NC} Kein Modell-Loading-Prozess in den Logs gefunden"
        fi
        
        # GPU-Nutzung
        if grep -q "CUDA is available" "$temp_log_file" || grep -q "Using device: cuda" "$temp_log_file"; then
            echo -e "${GREEN}✓${NC} CUDA ist verfügbar und wird genutzt"
            
            # Tensor-Parallelism
            if grep -q "tensor_parallel_size" "$temp_log_file"; then
                local tp_size=$(grep -o "tensor_parallel_size[^,]*" "$temp_log_file" | tail -1 | grep -o "[0-9]")
                echo -e "${GREEN}✓${NC} Tensor-Parallelism ist aktiv mit $tp_size GPUs"
            fi
        else
            echo -e "${RED}✗${NC} CUDA-Nutzung konnte nicht bestätigt werden"
        fi
        
        # Typische Fehler
        if grep -q "CUDA out of memory" "$temp_log_file"; then
            echo -e "${RED}✗${NC} CUDA Out-of-Memory-Fehler gefunden!"
            echo -e "   Empfehlung: Reduzieren Sie gpu-memory-utilization, verwenden Sie mehr GPUs,"
            echo -e "   oder wechseln Sie zu einem kleineren Modell."
        fi
        
        if grep -q "Error loading model" "$temp_log_file"; then
            echo -e "${RED}✗${NC} Fehler beim Laden des Modells!"
            local error_context=$(grep -A 5 "Error loading model" "$temp_log_file")
            echo -e "   Fehlerkontext: $error_context"
        fi
    elif [ "$component" == "webui" ]; then
        # WebUI-spezifische Analyse
        if grep -q "Connected to OpenAI API" "$temp_log_file" || grep -q "OPENAI_API_BASE_URL" "$temp_log_file"; then
            echo -e "${GREEN}✓${NC} WebUI ist mit OpenAI API verbunden"
        else
            echo -e "${YELLOW}⚠${NC} Keine Verbindung zur OpenAI API gefunden"
        fi
        
        # Server-Start
        if grep -q "FastAPI" "$temp_log_file" && grep -q "server up" "$temp_log_file"; then
            echo -e "${GREEN}✓${NC} WebUI-Server läuft und ist bereit"
        else
            echo -e "${YELLOW}⚠${NC} WebUI-Server wurde möglicherweise noch nicht vollständig gestartet"
        fi
    fi
    
    # Zeige die letzten Fehler und Warnungen
    if [ "$error_count" -gt 0 ]; then
        echo -e "\n${RED}Letzte Fehler:${NC}"
        grep -i "error\|exception\|fail" "$temp_log_file" | tail -5
    fi
    
    if [ "$warning_count" -gt 0 ]; then
        echo -e "\n${YELLOW}Letzte Warnungen:${NC}"
        grep -i "warn\|warning" "$temp_log_file" | tail -5
    fi
    
    # Aufräumen
    rm "$temp_log_file"
}

# Hauptlogik
if [ "$COMPONENT" == "all" ]; then
    if [ "$ANALYZE" = true ]; then
        analyze_logs "vllm"
        echo
        analyze_logs "webui"
    else
        show_logs "vllm"
        echo
        show_logs "webui"
    fi
else
    if [ "$ANALYZE" = true ]; then
        analyze_logs "$COMPONENT"
    else
        show_logs "$COMPONENT"
    fi
fi
