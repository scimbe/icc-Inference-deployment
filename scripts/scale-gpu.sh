#!/bin/bash

# Skript zum Skalieren der GPU-Ressourcen für vLLM-Deployment
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
    echo "Skript zum Skalieren der GPU-Ressourcen für vLLM-Deployment."
    echo
    echo "Optionen:"
    echo "  -c, --count NUM    Anzahl der GPUs (1-4, abhängig von Verfügbarkeit)"
    echo "  -h, --help         Diese Hilfe anzeigen"
    echo
    echo "Beispiel:"
    echo "  $0 --count 2       vLLM auf 2 GPUs skalieren"
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

# Überprüfe ob das vLLM Deployment existiert
if ! kubectl -n "$NAMESPACE" get deployment "$VLLM_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: vLLM Deployment '$VLLM_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

# Aktuelle GPU-Anzahl abrufen
CURRENT_GPU_COUNT=$(kubectl -n "$NAMESPACE" get deployment "$VLLM_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.nvidia\.com/gpu}')

echo "=== GPU-Skalierung für vLLM ==="
echo "Namespace: $NAMESPACE"
echo "Deployment: $VLLM_DEPLOYMENT_NAME"
echo "Aktuelle GPU-Anzahl: $CURRENT_GPU_COUNT"
echo "Neue GPU-Anzahl: $GPU_COUNT_NEW"

# Bestätigung einholen
if [[ "$GPU_COUNT_NEW" == "$CURRENT_GPU_COUNT" ]]; then
    echo "Die angeforderte GPU-Anzahl entspricht der aktuellen Konfiguration."
    echo "Keine Änderung erforderlich."
    exit 0
fi

echo
read -p "Möchten Sie die Skalierung durchführen? Dies wird einen Neustart des vLLM-Pods verursachen. (j/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    echo "Abbruch"
    exit 1
fi

# Temporäre Patchdateien erstellen
TMP_PATCH_GPU=$(mktemp)
TMP_PATCH_ARGS=$(mktemp)

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

# Extrahiere aktuelle args
CURRENT_ARGS=$(kubectl -n "$NAMESPACE" get deployment "$VLLM_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].args}')

# Identifiziere den aktuellen tensor-parallel-size Wert in den args
CURRENT_TP_ARG=$(echo "$CURRENT_ARGS" | grep -o -- "--tensor-parallel-size [0-9]" || echo "")

# Wenn ein tensor-parallel-size gefunden wurde, ersetze ihn
if [[ -n "$CURRENT_TP_ARG" ]]; then
    # Extrahiere den Wert
    CURRENT_TP_SIZE=${CURRENT_TP_ARG##* }
    
    if [[ "$CURRENT_TP_SIZE" != "$GPU_COUNT_NEW" ]]; then
        echo "Aktualisiere tensor-parallel-size von $CURRENT_TP_SIZE auf $GPU_COUNT_NEW..."
        
        # Erstelle einen JSON-Patch, der den alten arg durch einen neuen ersetzt
        cat << EOF > "$TMP_PATCH_ARGS"
[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0]/args",
    "value": [
      $(kubectl -n "$NAMESPACE" get deployment "$VLLM_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].args}' | sed "s/--tensor-parallel-size $CURRENT_TP_SIZE/--tensor-parallel-size $GPU_COUNT_NEW/g")
    ]
  }
]
EOF
    else
        echo "tensor-parallel-size ist bereits auf $GPU_COUNT_NEW gesetzt."
    fi
else
    # Wenn kein tensor-parallel-size gefunden wurde, füge ihn hinzu (wenn GPU_COUNT_NEW > 1)
    if [[ "$GPU_COUNT_NEW" -gt 1 ]]; then
        echo "Füge tensor-parallel-size=$GPU_COUNT_NEW zu den args hinzu..."
        
        # Hole aktuelle args als Array
        ARGS_ARRAY=$(kubectl -n "$NAMESPACE" get deployment "$VLLM_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].args}')
        
        # Füge den neuen arg hinzu (komplexer Fall, der Beachtung des JSON-Formats erfordert)
        # In diesem Fall wäre es einfacher, das Deployment neu zu starten, aber wir implementieren es hier der Vollständigkeit halber
        echo "Diese Operation erfordert einen vollständigen Neustart des Deployments."
        echo "Es wird empfohlen, das Deployment mit dem aktualisierten Wert in config.sh neu zu starten."
        
        read -p "Möchten Sie stattdessen das Deployment neu starten? (j/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Jj]$ ]]; then
            # Aktualisiere die GPU_COUNT in der config.sh
            sed -i "s/^export GPU_COUNT=.*/export GPU_COUNT=$GPU_COUNT_NEW/" "$ROOT_DIR/configs/config.sh"
            
            echo "GPU_COUNT in config.sh auf $GPU_COUNT_NEW aktualisiert."
            echo "Starte Deployment neu..."
            
            # Deployment neu starten
            bash "$ROOT_DIR/scripts/deploy-vllm.sh"
            exit 0
        fi
    fi
fi

# Wende GPU-Resource-Patch an
echo "Wende GPU-Resource-Patch an..."
kubectl -n "$NAMESPACE" patch deployment "$VLLM_DEPLOYMENT_NAME" --type=json --patch-file="$TMP_PATCH_GPU"

# Wenn tensor-parallel-size-Patch existiert, wende ihn an
if [[ -s "$TMP_PATCH_ARGS" ]]; then
    echo "Wende tensor-parallel-size-Patch an..."
    kubectl -n "$NAMESPACE" patch deployment "$VLLM_DEPLOYMENT_NAME" --type=json --patch-file="$TMP_PATCH_ARGS"
fi

# Aufräumen
rm "$TMP_PATCH_GPU" "$TMP_PATCH_ARGS"

# Warte auf das Rollout
echo "Warte auf Rollout der Änderungen..."
kubectl -n "$NAMESPACE" rollout status deployment/"$VLLM_DEPLOYMENT_NAME" --timeout=180s

# Aktualisierte Konfiguration anzeigen
echo "GPU-Skalierung abgeschlossen."
echo "Neue Konfiguration:"
kubectl -n "$NAMESPACE" get deployment "$VLLM_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].resources.limits}'
echo

# Hinweis zur Prüfung der GPU-Funktionalität
echo "Bitte prüfen Sie die GPU-Funktionalität mit:"
echo "  ./scripts/test-gpu.sh"

# Hinweis zur Konfigurationsdatei
echo
echo "Hinweis: Diese Änderung ist temporär und wird bei einem erneuten Deployment"
echo "mit den Werten aus der config.sh überschrieben. Um die Änderung permanent zu machen,"
echo "aktualisieren Sie den GPU_COUNT-Wert in Ihrer configs/config.sh."
