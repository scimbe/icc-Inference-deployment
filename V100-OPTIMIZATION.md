# V100 GPU-Optimierung für TGI

Diese Anleitung beschreibt, wie Sie Text Generation Inference (TGI) mit Tesla V100 GPUs auf der ICC der HAW Hamburg optimiert bereitstellen können.

## Problembeschreibung

TGI-Deployments auf Tesla V100 GPUs mit 16GB Speicher können Out-of-Memory-Fehler (OOM) verursachen, besonders bei Multi-GPU-Setups. Der typische Fehler ist:

```
Shard process was signaled to shutdown with signal 9
```

Dies liegt an den Speicherbeschränkungen der V100 GPUs und den speziellen Anforderungen der TGI-Version 1.2.0.

## Optimierte V100-Skripte

Für die stabile Ausführung auf V100 GPUs wurden folgende spezialisierte Skripte erstellt:

1. **scripts/deploy-tgi-v100.sh**:
   - Korrigierter Parameter `--cuda-memory-fraction` statt `--gpu-memory-utilization`
   - Optimiertes Speicher-Management mit reduzierten Token-Limits
   - Korrekte Formatierung der Kommandozeilen-Parameter
   - V100-spezifische NCCL-Optimierungen

2. **configs/config.v100.sh**:
   - Speicher-optimierte Werte für V100 GPUs
   - Aktivierte Quantisierung für bessere Memory-Effizienz
   - Angepasste Ressourcenlimits

## Verwendung

1. **Kopieren der V100-optimierten Konfiguration**:
   ```bash
   cp configs/config.v100.sh configs/config.sh
   ```

2. **Verwenden des V100-spezifischen Deployment-Skripts**:
   ```bash
   ./scripts/deploy-tgi-v100.sh
   ```

3. **Kompatibilitätstest durchführen**:
   ```bash
   ./scripts/test-v100-compatibility.sh
   ```

## Empfohlene Parameter für V100 GPUs

### Für eine einzelne V100 GPU (16GB):

```bash
export MODEL_NAME="microsoft/phi-2"  # Kleines 2.7B-Modell
export QUANTIZATION="awq"            # Speichereffiziente Quantisierung
export CUDA_MEMORY_FRACTION=0.85     # 85% des GPU-Speichers verwenden
export MAX_INPUT_LENGTH=2048         # Reduzierte Kontextlänge
export MAX_TOTAL_TOKENS=4096         # Reduzierte Gesamttokens
export DSHM_SIZE="4Gi"               # Shared Memory für eine GPU
```

### Für Multi-GPU V100-Setup (2x 16GB):

```bash
export MODEL_NAME="mistralai/Mistral-7B-Instruct-v0.2"  # 7B-Modell
export GPU_COUNT=2                                       # 2 GPUs
export QUANTIZATION="awq"                                # Speichereffiziente Quantisierung
export CUDA_MEMORY_FRACTION=0.85                         # 85% des GPU-Speichers verwenden
export MAX_INPUT_LENGTH=4096                             # Höhere Kontextlänge mit 2 GPUs
export MAX_TOTAL_TOKENS=8192                             # Höhere Gesamttokens mit 2 GPUs
export DSHM_SIZE="8Gi"                                   # Erhöhter Shared Memory für Multi-GPU
```

## Modellgrößen-Empfehlungen für V100 GPUs

| Modellgröße | GPU-Setup       | Quantisierung | Empfohlenes Modell                  |
|-------------|-----------------|---------------|-------------------------------------|
| 1-3B        | 1x V100 (16GB)  | Keine         | microsoft/phi-2, google/gemma-2b    |
| 7B          | 1x V100 (16GB)  | AWQ           | Mistral-7B, Llama-2-7b              |
| 7B          | 2x V100 (32GB)  | Keine         | Mistral-7B, Llama-2-7b              |
| 13B         | 2x V100 (32GB)  | AWQ           | Llama-2-13b                         |
| 13B         | 4x V100 (64GB)  | Keine         | Llama-2-13b                         |

## Fehlerbehebung

Falls nach den Optimierungen weiterhin OOM-Fehler auftreten:

1. **Reduzieren Sie die Modellgröße** auf unter 7B Parameter
2. **Aktivieren Sie AWQ-Quantisierung** mit `export QUANTIZATION="awq"`
3. **Reduzieren Sie die Token-Limits** weiter: `MAX_INPUT_LENGTH=1024` und `MAX_TOTAL_TOKENS=2048` 
4. **Erhöhen Sie die Anzahl der GPUs** auf 2 oder mehr
5. **Reduzieren Sie die Speichernutzung** mit `CUDA_MEMORY_FRACTION=0.8`

## Hinweise

- Die CPU-Speicheranforderungen sind ebenfalls wichtig; stellen Sie sicher, dass `MEMORY_LIMIT` angemessen eingestellt ist
- Die `--sharded=true`-Option funktioniert nur bei mehreren GPUs
- Für Produktionsumgebungen empfehlen wir mindestens 2 V100 GPUs für Modelle ab 7B Parameter
- Der Parameter `NCCL_DEBUG=INFO` hilft bei der Diagnose von Multi-GPU-Kommunikationsproblemen

## GPU-Debugging

Für detaillierte Debugging-Informationen und GPU-Überwachung:

```bash
# Überwachen der GPU-Auslastung in Echtzeit
./scripts/monitor-gpu.sh

# Überprüfen der TGI-Logs auf Fehler
./scripts/check-logs.sh tgi -a

# Testen der V100-Kompatibilität
./scripts/test-v100-compatibility.sh
```

## Bekannte Probleme und deren Lösungen

### Problem 1: Fehlerhafte Parameterformatierung

**Symptom:** In den Logs erscheinen Parameter ohne Leerzeichen dazwischen, z.B. `--model-id=microsoft/phi-2--port=8000`

**Lösung:** Verwenden Sie das aktualisierte `deploy-tgi-v100.sh` Skript, das korrekte Parametertrennung gewährleistet.

### Problem 2: Out-of-Memory beim Multi-GPU-Setup

**Symptom:** `Shard process was signaled to shutdown with signal 9`

**Lösungen:**
- Erhöhen Sie `DSHM_SIZE` auf "16Gi" für bessere Inter-GPU-Kommunikation
- Setzen Sie `NCCL_P2P_LEVEL=NVL` und `NCCL_SOCKET_IFNAME="^lo,docker"` für optimierte Kommunikation
- Reduzieren Sie die Modellgröße oder verwenden Sie Quantisierung

### Problem 3: Langsamer Start oder Timeout

**Symptom:** Das Deployment startet nicht oder braucht extrem lange

**Lösungen:**
- Prüfen Sie die Netzwerkverbindung zum HuggingFace Hub
- Nutzen Sie ein lokal gespeichertes Modell, falls möglich
- Beginnen Sie mit einem kleinen Modell wie TinyLlama, um die Grundfunktionalität zu testen

## Beispiel für ein erfolgreiches Multi-GPU-Setup

Hier ein Beispiel für ein erfolgreiches Deployment mit Mistral-7B auf 2 V100 GPUs:

```yaml
NAMESPACE="wXYZ123-default"
MODEL_NAME="mistralai/Mistral-7B-Instruct-v0.2"
GPU_COUNT=2
QUANTIZATION="awq"
MAX_INPUT_LENGTH=2048
MAX_TOTAL_TOKENS=4096
CUDA_MEMORY_FRACTION=0.85
DSHM_SIZE="8Gi"
MEMORY_LIMIT="24Gi"
```

Führen Sie das Deployment mit `./scripts/deploy-tgi-v100.sh` durch.

## Nächste Schritte

Nach erfolgreichem Deployment können Sie:

1. Die WebUI für einfache Benutzerinteraktion einrichten: `./scripts/deploy-webui.sh`
2. GPU-Ressourcen bei Bedarf dynamisch skalieren: `./scripts/scale-gpu.sh --count <1-4>`
3. Die API direkt ansprechen für programmatischen Zugriff über Port 3333
