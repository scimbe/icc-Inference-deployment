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
    echo "  -m, --mem SIZE     Shared Memory Größe (z.B. 8Gi, 16Gi)"
    echo "  -h, --help         Diese Hilfe anzeigen"
    echo
    echo "Beispiel:"
    echo "  $0 --count 2       TGI auf 2 GPUs skalieren"
    echo "  $0 --count 2 --mem 16Gi   TGI auf 2 GPUs mit 16GB Shared Memory skalieren"
    exit 0
}

# Parameter parsen
GPU_COUNT_NEW=""
DSHM_SIZE_NEW=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--count)
            GPU_COUNT_NEW="$2"
            shift 2
            ;;
        -m|--mem)
            DSHM_SIZE_NEW="$2"
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
if [[ -z "$GPU_COUNT_NEW" && -z "$DSHM_SIZE_NEW" ]]; then
    echo "Fehler: Mindestens GPU-Anzahl oder Shared Memory Größe muss angegeben werden."
    show_help
fi

# Validiere GPU-Anzahl
if [[ -n "$GPU_COUNT_NEW" ]]; then
    if ! [[ "$GPU_COUNT_NEW" =~ ^[1-4]$ ]]; then
        echo "Fehler: GPU-Anzahl muss zwischen 1 und 4 liegen."
        exit 1
    fi
fi

# Überprüfe ob das TGI Deployment existiert
if ! kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" &> /dev/null; then
    echo "Fehler: TGI Deployment '$TGI_DEPLOYMENT_NAME' nicht gefunden."
    echo "Bitte führen Sie zuerst deploy.sh aus."
    exit 1
fi

# Aktuelle GPU-Anzahl abrufen
CURRENT_GPU_COUNT=$(kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.nvidia\.com/gpu}')
CURRENT_DSHM_SIZE=$(kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.volumes[?(@.name=="dshm")].emptyDir.sizeLimit}')

# Setze GPU-Anzahl falls nicht angegeben
if [[ -z "$GPU_COUNT_NEW" ]]; then
    GPU_COUNT_NEW=$CURRENT_GPU_COUNT
fi

# Setze Shared Memory-Größe falls nicht angegeben
if [[ -z "$DSHM_SIZE_NEW" ]]; then
    DSHM_SIZE_NEW=$CURRENT_DSHM_SIZE
fi

echo "=== GPU-Skalierung für TGI ==="
echo "Namespace: $NAMESPACE"
echo "Deployment: $TGI_DEPLOYMENT_NAME"
echo "Aktuelle GPU-Anzahl: $CURRENT_GPU_COUNT"
echo "Neue GPU-Anzahl: $GPU_COUNT_NEW"
echo "Aktueller Shared Memory: $CURRENT_DSHM_SIZE"
echo "Neuer Shared Memory: $DSHM_SIZE_NEW"

# Bestätigung einholen
if [[ "$GPU_COUNT_NEW" == "$CURRENT_GPU_COUNT" && "$DSHM_SIZE_NEW" == "$CURRENT_DSHM_SIZE" ]]; then
    echo "Die angeforderte Konfiguration entspricht der aktuellen Konfiguration."
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
TMP_PATCH_CONFIG=$(mktemp)

# Erstelle einen komplexen Patch für mehrere Änderungen
cat << EOF > "$TMP_PATCH_CONFIG"
{
  "spec": {
    "template": {
      "spec": {
EOF

# Füge GPU-Ressourcen hinzu, wenn sich die Anzahl geändert hat
if [[ "$GPU_COUNT_NEW" != "$CURRENT_GPU_COUNT" ]]; then
    cat << EOF >> "$TMP_PATCH_CONFIG"
        "containers": [
          {
            "name": "tgi",
            "resources": {
              "limits": {
                "nvidia.com/gpu": $GPU_COUNT_NEW
              }
            }
          }
        ],
EOF
fi

# Füge DSHM-Volume-Änderung hinzu, wenn sich die Größe geändert hat
if [[ "$DSHM_SIZE_NEW" != "$CURRENT_DSHM_SIZE" ]]; then
    cat << EOF >> "$TMP_PATCH_CONFIG"
        "volumes": [
          {
            "name": "dshm",
            "emptyDir": {
              "medium": "Memory",
              "sizeLimit": "$DSHM_SIZE_NEW"
            }
          },
          {
            "name": "model-cache",
            "emptyDir": {}
          }
        ],
EOF
fi

# Schließe JSON-Struktur
cat << EOF >> "$TMP_PATCH_CONFIG"
      }
    }
  }
}
EOF

# Wende Patch an
echo "Wende Konfigurationsänderungen an..."
kubectl -n "$NAMESPACE" patch deployment "$TGI_DEPLOYMENT_NAME" --type=merge --patch-file="$TMP_PATCH_CONFIG"

# CUDA_DEVICES aktualisieren, wenn sich die GPU-Anzahl geändert hat
if [[ "$GPU_COUNT_NEW" != "$CURRENT_GPU_COUNT" ]]; then
    # CUDA_DEVICES bauen
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
    "path": "/spec/template/spec/containers/0/env/0/value",
    "value": "$CUDA_DEVICES"
  }
]
EOF

    echo "Aktualisiere CUDA_VISIBLE_DEVICES auf $CUDA_DEVICES..."
    kubectl -n "$NAMESPACE" patch deployment "$TGI_DEPLOYMENT_NAME" --type=json --patch-file="$TMP_PATCH_CUDA"
    rm "$TMP_PATCH_CUDA"

    # Sharded-Modus aktivieren oder deaktivieren
    TMP_PATCH_ARGS=$(mktemp)

    # Prüfe, ob der aktuelle Args-Array den "--sharded=true" Parameter enthält
    CURRENT_ARGS=$(kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].args}')
    HAS_SHARDED=$(echo "$CURRENT_ARGS" | grep -q -- "--sharded=true" && echo "true" || echo "false")
    
    # Prüfe, ob der aktuelle Args-Array den "--num-shard" Parameter enthält
    HAS_NUM_SHARD=$(echo "$CURRENT_ARGS" | grep -q -- "--num-shard" && echo "true" || echo "false")

    # Erstelle separate JSON-Patches für Shard-Konfiguration
    if [ "$GPU_COUNT_NEW" -gt 1 ] && [ "$HAS_SHARDED" = "false" ]; then
        # Füge sharded=true hinzu, wenn mehrere GPUs und noch nicht gesetzt
        cat << EOF > "$TMP_PATCH_ARGS"
[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--sharded=true"
  }
]
EOF
        echo "Aktiviere Sharded-Modus für Multi-GPU-Konfiguration..."
        kubectl -n "$NAMESPACE" patch deployment "$TGI_DEPLOYMENT_NAME" --type=json --patch-file="$TMP_PATCH_ARGS"
    elif [ "$GPU_COUNT_NEW" -eq 1 ] && [ "$HAS_SHARDED" = "true" ]; then
        # Entferne sharded=true, wenn nur eine GPU und bereits gesetzt
        ARGS=$(kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].args}')
        SHARDED_INDEX=""
        
        # Konvertiere das JSON-Array in eine Bash-Array
        ARGS_ARRAY=()
        idx=0
        while read -r arg; do
            ARGS_ARRAY[idx]="$arg"
            if [[ "$arg" == "--sharded=true" ]]; then
                SHARDED_INDEX=$idx
            fi
            ((idx++))
        done < <(echo "$ARGS" | tr -d '[],"' | tr ' ' '\n' | grep -v '^$')
        
        if [ -n "$SHARDED_INDEX" ]; then
            cat << EOF > "$TMP_PATCH_ARGS"
[
  {
    "op": "remove",
    "path": "/spec/template/spec/containers/0/args/$SHARDED_INDEX"
  }
]
EOF
            echo "Deaktiviere Sharded-Modus für Single-GPU-Konfiguration..."
            kubectl -n "$NAMESPACE" patch deployment "$TGI_DEPLOYMENT_NAME" --type=json --patch-file="$TMP_PATCH_ARGS"
        fi
    fi

    # Aktualisiere oder füge num-shard Parameter hinzu für A100 GPUs
    if [[ "$GPU_TYPE" == "gpu-tesla-a100" ]]; then
        if [ "$HAS_NUM_SHARD" = "true" ]; then
            # Finde den Index des num-shard Parameters
            ARGS=$(kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].args}')
            NUM_SHARD_INDEX=""
            
            # Konvertiere das JSON-Array in eine Bash-Array
            ARGS_ARRAY=()
            idx=0
            while read -r arg; do
                ARGS_ARRAY[idx]="$arg"
                if [[ "$arg" == "--num-shard="* ]]; then
                    NUM_SHARD_INDEX=$idx
                fi
                ((idx++))
            done < <(echo "$ARGS" | tr -d '[],"' | tr ' ' '\n' | grep -v '^$')
            
            if [ -n "$NUM_SHARD_INDEX" ]; then
                cat << EOF > "$TMP_PATCH_ARGS"
[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/args/$NUM_SHARD_INDEX",
    "value": "--num-shard=$GPU_COUNT_NEW"
  }
]
EOF
                echo "Aktualisiere num-shard Parameter für A100 Multi-GPU-Konfiguration..."
                kubectl -n "$NAMESPACE" patch deployment "$TGI_DEPLOYMENT_NAME" --type=json --patch-file="$TMP_PATCH_ARGS"
            fi
        elif [ "$GPU_COUNT_NEW" -gt 1 ]; then
            # Füge num-shard hinzu wenn noch nicht vorhanden
            cat << EOF > "$TMP_PATCH_ARGS"
[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--num-shard=$GPU_COUNT_NEW"
  }
]
EOF
            echo "Füge num-shard Parameter für A100 Multi-GPU-Konfiguration hinzu..."
            kubectl -n "$NAMESPACE" patch deployment "$TGI_DEPLOYMENT_NAME" --type=json --patch-file="$TMP_PATCH_ARGS"
        fi
    fi

    rm "$TMP_PATCH_ARGS"
fi

# Aufräumen
rm "$TMP_PATCH_CONFIG"

# Warte auf das Rollout
echo "Warte auf Rollout der Änderungen..."
kubectl -n "$NAMESPACE" rollout status deployment/"$TGI_DEPLOYMENT_NAME" --timeout=180s

# Aktualisierte Konfiguration anzeigen
echo "GPU-Skalierung abgeschlossen."
echo "Neue Konfiguration:"
kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.containers[0].resources.limits}'
echo -e "\nShared Memory: $(kubectl -n "$NAMESPACE" get deployment "$TGI_DEPLOYMENT_NAME" -o jsonpath='{.spec.template.spec.volumes[?(@.name=="dshm")].emptyDir.sizeLimit}')"

# Hinweis zur Prüfung der GPU-Funktionalität
echo
echo "Bitte prüfen Sie die GPU-Funktionalität mit:"
echo "  ./scripts/test-gpu.sh"

# Hinweis zur Konfigurationsdatei
echo
echo "Hinweis: Diese Änderung ist temporär und wird bei einem erneuten Deployment"
echo "mit den Werten aus der config.sh überschrieben. Um die Änderung permanent zu machen,"
echo "aktualisieren Sie die entsprechenden Werte in Ihrer configs/config.sh."