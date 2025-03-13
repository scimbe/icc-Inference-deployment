#!/bin/bash

# Skript zum Ändern des Modells im vLLM-Deployment
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

# Hilfsfunktion: Zeige Hilfe an
show_help() {
    echo "Verwendung: $0 [OPTIONEN]"
    echo
    echo "Skript zum Ändern des Modells im vLLM-Deployment."
    echo
    echo "Optionen:"
    echo "  -m, --model NAME      Modellname oder HuggingFace-Pfad (z.B. meta-llama/Llama-2-7b-chat-hf)"
    echo "  -q, --quantization    Aktiviere Quantisierung (awq oder gptq)"
    echo "  -l, --max-len NUM     Maximale Kontextlänge (Standard: aktuelle Einstellung beibehalten)"
    echo "  -t, --temp NUM        Inferenz-Temperatur (0.0-1.0, Standard: aktuelle Einstellung beibehalten)"
    echo "  -h, --help            Diese Hilfe anzeigen"
    echo
    echo "Beispiel:"
    echo "  $0 --model meta-llama/Llama-2-7b-chat-hf --quantization awq"
    echo "  $0 --model google/gemma-7b-it --max-len 4096"
    exit 0
}

# Standardwerte
NEW_MODEL=""
NEW_QUANTIZATION=""
NEW_MAX_MODEL_LEN=""
NEW_TEMPERATURE=""

# Parameter parsen
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--model)
            NEW_MODEL="$2"
            shift 2
            ;;
        -q|--quantization)
            NEW_QUANTIZATION="$2"
            shift 2
            ;;
        -l|--max-len)
            NEW_MAX_MODEL_LEN="$2"
            shift 2
            ;;
        -t|--temp)
            NEW_TEMPERATURE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unbekannte Option: $1"
            show_help
            ;;
    esac
done

# Überprüfe Eingabeparameter
if [[ -z "$NEW_MODEL" ]]; then
    echo "Fehler: Modellname muss angegeben werden."
    show_help
fi

# Überprüfe ob das vLLM Deployment existiert
if ! kubectl -n "$NAMESPACE" get deployment "$VLLM_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: vLLM Deployment '$VLLM_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

# Aktuelles Modell anzeigen
echo "=== Modellwechsel für vLLM ==="
echo "Namespace: $NAMESPACE"
echo "Deployment: $VLLM_DEPLOYMENT_NAME"
echo "Aktuelles Modell: $MODEL_NAME"
echo "Neues Modell: $NEW_MODEL"

if [ -n "$NEW_QUANTIZATION" ]; then
    echo "Neue Quantisierung: $NEW_QUANTIZATION"
fi

if [ -n "$NEW_MAX_MODEL_LEN" ]; then
    echo "Neue maximale Kontextlänge: $NEW_MAX_MODEL_LEN"
fi

if [ -n "$NEW_TEMPERATURE" ]; then
    echo "Neue Temperatur: $NEW_TEMPERATURE"
fi

# Bestätigung einholen
echo
read -p "Möchten Sie das Modell wechseln? Dies wird einen Neustart des vLLM-Pods verursachen. (j/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Abbruch"
    exit 1
fi

# Aktualisiere die Konfigurationsdatei
echo "Aktualisiere Konfiguration in config.sh..."

# Modell ändern
sed -i "s|^export MODEL_NAME=.*|export MODEL_NAME=\"$NEW_MODEL\"|" "$ROOT_DIR/configs/config.sh"

# Quantisierung ändern, falls angegeben
if [ -n "$NEW_QUANTIZATION" ]; then
    sed -i "s|^export QUANTIZATION=.*|export QUANTIZATION=\"$NEW_QUANTIZATION\"|" "$ROOT_DIR/configs/config.sh"
fi

# Maximale Kontextlänge ändern, falls angegeben
if [ -n "$NEW_MAX_MODEL_LEN" ]; then
    sed -i "s|^export MAX_MODEL_LEN=.*|export MAX_MODEL_LEN=$NEW_MAX_MODEL_LEN|" "$ROOT_DIR/configs/config.sh"
fi

# Temperatur ändern, falls angegeben
if [ -n "$NEW_TEMPERATURE" ]; then
    TEMP_LINE_EXISTS=$(grep -c "^export TEMPERATURE=" "$ROOT_DIR/configs/config.sh" || true)
    if [ "$TEMP_LINE_EXISTS" -gt 0 ]; then
        sed -i "s|^export TEMPERATURE=.*|export TEMPERATURE=$NEW_TEMPERATURE|" "$ROOT_DIR/configs/config.sh"
    else
        echo "export TEMPERATURE=$NEW_TEMPERATURE" >> "$ROOT_DIR/configs/config.sh"
    fi
fi

# Lade die aktualisierte Konfiguration
source "$ROOT_DIR/configs/config.sh"

# Deployment neu starten
echo "Starte vLLM-Deployment mit neuem Modell..."
"$ROOT_DIR/scripts/deploy-vllm.sh"

echo "Modellwechsel abgeschlossen."
echo "Das neue Modell '$MODEL_NAME' wird beim Start geladen."
echo "HINWEIS: Das Laden des neuen Modells kann je nach Größe einige Zeit in Anspruch nehmen."
echo "Überwachen Sie den Fortschritt mit: kubectl -n $NAMESPACE logs -f deployment/$VLLM_DEPLOYMENT_NAME"
