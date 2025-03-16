# Fehlerbehebung für ICC vLLM/TGI Deployment

Dieses Dokument enthält Lösungen für häufige Probleme, die bei der Verwendung des ICC vLLM/TGI Deployment-Systems auftreten können. Für eine umfassendere Liste an Lösungen siehe auch die [COMMANDS.md](COMMANDS.md).

## Inhalt

- [vLLM Parameter-Fehler](#vllm-parameter-fehler)
- [Out-of-Memory (OOM) Fehler](#out-of-memory-oom-fehler)
- [Modell lädt nicht](#modell-lädt-nicht)
- [GPU-Probleme](#gpu-probleme)
- [Allgemeine Tipps](#allgemeine-tipps)

## vLLM Parameter-Fehler

### Problem: Unbekanntes `--max-batch-size` Argument

```
api_server.py: error: unrecognized arguments: --max-batch-size 32
```

**Erklärung:**  
Neuere Versionen von vLLM verwenden möglicherweise unterschiedliche Befehlszeilenargumente als ältere Versionen. Der Parameter `--max-batch-size` wird in einigen Versionen nicht unterstützt.

### Lösungen:

1. **Automatische Behebung:**  
   Das aktuelle vLLM-Deployment-Skript (`scripts/deploy-vllm-v100.sh`) erkennt automatisch, wenn `--max-batch-size` nicht unterstützt wird, und überspringt den Parameter.

2. **Manuelle Behebung:**
   - Bearbeiten Sie `configs/config.sh` und kommentieren Sie die Zeile mit `MAX_BATCH_SIZE` aus:
   ```bash
   # export MAX_BATCH_SIZE=32  # Diesen Parameter auskommentieren oder entfernen
   ```
   - Oder ändern Sie die Batch-Größe zu einem niedrigeren Wert:
   ```bash
   export MAX_BATCH_SIZE=8  # Niedrigerer Wert kann in einigen Fällen funktionieren
   ```

3. **Alternative Parameter prüfen:**
   - Überprüfen Sie die aktuelle vLLM-Dokumentation für Ihre Version:
   ```bash
   # Im Pod ausführen:
   kubectl -n $NAMESPACE exec $POD_NAME -- vllm --help
   ```
   - Verwenden Sie ggf. alternative Parameter, die in Ihrer vLLM-Version unterstützt werden

## Out-of-Memory (OOM) Fehler

### Problem: Pod beendet sich mit Fehlermeldungen wie

```
Shard process was signaled to shutdown with signal 9
CUDA error: out of memory
```

### Lösungen:

1. **Kleineres Modell verwenden:**
   ```bash
   ./scripts/change-model.sh --model "microsoft/phi-2"
   ```

2. **Quantisierung aktivieren (für 7B+ Modelle):**
   ```bash
   ./scripts/change-model.sh --model "mistralai/Mistral-7B-Instruct-v0.2" --quantization awq
   ```

3. **Mehr GPUs verwenden:**
   ```bash
   ./scripts/scale-gpu.sh --count 2
   ```

4. **Kontextfenster reduzieren:**
   Bearbeiten Sie `config.sh` und reduzieren Sie:
   ```bash
   export MAX_INPUT_LENGTH=1024
   export MAX_TOTAL_TOKENS=2048
   ```

5. **Shared Memory erhöhen:**
   ```bash
   ./scripts/scale-gpu.sh --mem 16Gi
   ```

## Modell lädt nicht

### Problem: Der Pod startet, aber das Modell wird nicht geladen

### Lösungen:

1. **Logs prüfen:**
   ```bash
   ./scripts/check-logs.sh tgi
   # oder
   ./scripts/check-logs.sh vllm
   ```

2. **Hugging Face Token für geschützte Modelle setzen:**
   Bearbeiten Sie `config.sh`:
   ```bash
   export HUGGINGFACE_TOKEN="hf_..."
   ```

3. **Minimales Testdeployment ausführen:**
   ```bash
   ./scripts/deploy-tgi-minimal.sh
   # oder
   ./scripts/deploy-vllm-minimal.sh
   ```

4. **Auf ein öffentliches Modell wechseln:**
   ```bash
   ./scripts/change-model.sh --model "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
   ```

## GPU-Probleme

### Problem: GPU wird nicht erkannt oder falsch konfiguriert

### Lösungen:

1. **GPU-Kompatibilität prüfen:**
   ```bash
   ./scripts/test-v100-compatibility.sh
   ```

2. **GPU-Ressourcen im Cluster prüfen:**
   ```bash
   kubectl describe nodes | grep -A 5 "nvidia.com/gpu"
   ```

3. **GPU-Tolerations überprüfen:**
   Stellen Sie sicher, dass `GPU_TYPE` in `config.sh` korrekt ist:
   ```bash
   export GPU_TYPE="gpu-tesla-v100"  # oder entsprechender GPU-Typ
   ```

4. **GPU-Monitoring aktivieren:**
   ```bash
   ./scripts/monitor-gpu.sh -f full
   ```

## Allgemeine Tipps

1. **Deployment zurücksetzen und neu starten:**
   ```bash
   ./scripts/cleanup.sh
   ./deploy-v100.sh
   ```

2. **Aktuelle Pod-Details anzeigen:**
   ```bash
   kubectl -n $NAMESPACE describe pod -l app=llm-server
   # oder
   kubectl -n $NAMESPACE describe pod -l service=vllm-server
   ```

3. **Kubernetes-Events prüfen:**
   ```bash
   kubectl -n $NAMESPACE get events | grep -i error
   ```

4. **Support-Informationen sammeln:**
   ```bash
   ./scripts/collect-support-info.sh
   ```
   
5. **Aktuelle Kubernetes-Ressourcen auflisten:**
   ```bash
   kubectl -n $NAMESPACE get all
   ```

Falls Sie weitere Hilfe benötigen, konsultieren Sie bitte die umfassende Dokumentation in:
- [COMMANDS.md](COMMANDS.md) - Vollständige Befehlsreferenz
- [V100-OPTIMIZATION.md](V100-OPTIMIZATION.md) - V100-spezifische Optimierungen
- [DOCUMENTATION.md](DOCUMENTATION.md) - Detaillierte Projektdokumentation
