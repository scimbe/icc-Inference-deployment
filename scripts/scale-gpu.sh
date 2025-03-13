#!/bin/bash

# Skript zum Skalieren der GPU-Ressourcen für TGI-Deployment
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

# Hilfe-Funktion
show_help() {
    echo "Verwendung: $0 [OPTIONEN]"
    echo
    echo "Skript zum Skalieren der GPU-Ressourcen für TGI-Deployment."
    echo
    echo "Optionen:"
    echo "  -c, --count NUM    Anzahl der GPUs (1-4, abhängig von Verfügbarkeit)"
    echo "  -h, --help         Diese Hilfe anzeigen"
    echo
    echo "Beispiel:"
    echo "  $0 --count 2       TGI auf 2 GPUs skalieren"
    exit 0
}

# Parameter parsen
GPU_COUNT_NEW=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--count)
            GPU_COUNT_NEW="$2"
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
if [[ -z "$GPU_COUNT_NEW" ]]; then
    echo "Fehler: GPU-Anzahl muss angegeben werden."
    show_help
fi

# Validiere GPU-Anzahl
if ! [[ "$GPU_COUNT_NEW" =~ ^[1-4]$ ]]; then
    echo "Fehler: GPU-Anzahl muss zwischen 1 und 4 liegen."
    exit 1
fi

# Überprüfe ob das TGI Deployment existiert
if ! kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: TGI Deployment '$TGI_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

# Aktuelle GPU-Anzahl abrufen
CURRENT_GPU_COUNT=$(kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.nvidia\.com/gpu}')

echo "=== GPU-Skalierung für TGI ==="
echo "Namespace: $NAMESPACE"
echo "Deployment: $TGI_DEPLOYMENT_NAME"
echo "Aktuelle GPU-Anzahl: $CURRENT_GPU_COUNT"
echo "Neue GPU-Anzahl: $GPU_COUNT_NEW"

# Bestätigung einholen
if [[ "$GPU_COUNT_NEW" == "$CURRENT_GPU_COUNT" ]]; then
    echo "Die angeforderte GPU-Anzahl entspricht der aktuellen Konfiguration."
    echo "Keine Änderung erforderlich."
    exit 0
fi

echo
read -p "Möchten Sie die Skalierung durchführen? Dies wird einen Neustart des TGI-Pods verursachen. (j/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Abbruch"
    exit 1
fi

# Temporäre Patchdateien erstellen
TMP_PATCH_GPU=$(mktemp)

# Patch für GPU-Ressourcen
cat << EOF > "$TMP_PATCH_GPU"
[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/limits/nvidia.com~1gpu",
    "value": $GPU_COUNT_NEW
  }
]
EOF

# CUDA_DEVICES aktualisieren
CUDA_DEVICES="0"
if [ "$GPU_COUNT_NEW" -gt 1 ]; then
    for ((i=1; i<GPU_COUNT_NEW; i++)); do
        CUDA_DEVICES="${CUDA_DEVICES},$i"
    done
fi

# Patch für CUDA_DEVICES
TMP_PATCH_CUDA=$(mktemp)
cat << EOF > "$TMP_PATCH_CUDA"
[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/env",
    "value": $(kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].env}' | sed "s/CUDA_VISIBLE_DEVICES\":[^}]*}/CUDA_VISIBLE_DEVICES\": \"$CUDA_DEVICES\"}/")
  }
]
EOF

# Sharded-Modus aktivieren oder deaktivieren
TMP_PATCH_SHARDED=$(mktemp)

# Prüfe, ob der Sharded-Flag in den aktuellen Args vorhanden ist
CURRENT_ARGS=$(kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].args}')
HAS_SHARDED=$(echo "$CURRENT_ARGS" | grep -q -- "--sharded=true" && echo "true" || echo "false")

if [ "$GPU_COUNT_NEW" -gt 1 ] && [ "$HAS_SHARDED" = "false" ]; then
    # Füge sharded=true hinzu, wenn mehrere GPUs und noch nicht gesetzt
    cat << EOF > "$TMP_PATCH_SHARDED"
[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--sharded=true"
  }
]
EOF
    echo "Aktiviere Sharded-Modus für Multi-GPU-Konfiguration..."
    kubectl -n "$NAMESPACE" patch deployment "$TGI_DEPLOYMENT_NAME" --type=json --patch-file="$TMP_PATCH_SHARDED"
elif [ "$GPU_COUNT_NEW" -eq 1 ] && [ "$HAS_SHARDED" = "true" ]; then
    # Entferne sharded=true, wenn nur eine GPU und bereits gesetzt
    # Finde den Index des Sharded-Args
    ARGS=$(kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].args}')
    SHARDED_INDEX=""
    
    # Konvertiere das JSON-Array in eine Bash-Array
    eval "ARGS_ARRAY=($ARGS)"
    
    # Finde den Index von "--sharded=true"
    for i in "${!ARGS_ARRAY[@]}"; do
        if [[ "${ARGS_ARRAY[$i]}" == "--sharded=true" ]]; then
            SHARDED_INDEX=$i
            break
        fi
    done
    
    if [ -n "$SHARDED_INDEX" ]; then
        cat << EOF > "$TMP_PATCH_SHARDED"
[
  {
    "op": "remove",
    "path": "/spec/template/spec/containers/0/args/$SHARDED_INDEX"
  }
]
EOF
        echo "Deaktiviere Sharded-Modus für Single-GPU-Konfiguration..."
        kubectl -n "$NAMESPACE" patch deployment "$TGI_DEPLOYMENT_NAME" --type=json --patch-file="$TMP_PATCH_SHARDED"
    fi
fi

# Wende GPU-Resource-Patch an
echo "Wende GPU-Resource-Patch an..."
kubectl -n "$NAMESPACE" patch deployment "$TGI_DEPLOYMENT_NAME" --type=json --patch-file="$TMP_PATCH_GPU"

# Wende CUDA_DEVICES-Patch an
echo "Aktualisiere CUDA_VISIBLE_DEVICES..."
kubectl -n "$NAMESPACE" patch deployment "$TGI_DEPLOYMENT_NAME" --type=json --patch-file="$TMP_PATCH_CUDA"

# Aufräumen
rm "$TMP_PATCH_GPU" "$TMP_PATCH_CUDA" "$TMP_PATCH_SHARDED"

# Warte auf das Rollout
echo "Warte auf Rollout der Änderungen..."
kubectl -n "$NAMESPACE" rollout status deployment/"$TGI_DEPLOYMENT_NAME" --timeout=180s

# Aktualisierte Konfiguration anzeigen
echo "GPU-Skalierung abgeschlossen."
echo "Neue Konfiguration:"
kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].resources.limits}'
echo

# Hinweis zur Prüfung der GPU-Funktionalität
echo "Bitte prüfen Sie die GPU-Funktionalität mit:"
echo "  ./scripts/test-gpu.sh"

# Hinweis zur Konfigurationsdatei
echo
echo "Hinweis: Diese Änderung ist temporär und wird bei einem erneuten Deployment"
echo "mit den Werten aus der config.sh überschrieben. Um die Änderung permanent zu machen,"
echo "aktualisieren Sie den GPU_COUNT-Wert in Ihrer configs/config.sh."
