# ICC V100 LLM Deployment - Befehlsreferenz

Diese Referenz enthält alle wichtigen Befehle zur Verwaltung Ihres LLM-Deployments (TGI oder vLLM) auf der ICC mit V100 GPU-Unterstützung.

## 📚 Inhaltsverzeichnis

- [Schnellstart](#schnellstart)
- [Deployment-Befehle](#deployment-befehle)
- [Zugriff und Monitoring](#zugriff-und-monitoring)
- [Modell- und GPU-Verwaltung](#modell--und-gpu-verwaltung)
- [Fehlerbehebung](#fehlerbehebung)
- [Modellempfehlungen für V100 GPUs](#modellempfehlungen-für-v100-gpus)
- [Beispiele](#beispiele)

## 🚀 Schnellstart

```bash
# 1. Repository klonen und Verzeichnis wechseln
git clone https://github.com/scimbe/icc-llm-deployment.git
cd icc-llm-deployment

# 2. Skript-Berechtigungen setzen
chmod +x scripts/*.sh chmod +x *.sh

# 3. ICC-Zugang einrichten (einmalig)
./scripts/icc-login.sh

# 4. V100-optimierte Konfiguration erstellen
cp configs/config.v100.sh configs/config.sh

# 5. Konfiguration anpassen (wichtig!)
# - Namespace auf Ihre w-Kennung + "-default" setzen
# - Modell wählen
nano configs/config.sh

# 6. Deployment starten (interaktiv)
./deploy-v100.sh

# 7. ODER: Direkt TGI mit V100-Optimierung starten
./scripts/deploy-tgi-v100.sh

# 8. WebUI installieren
./scripts/deploy-webui.sh

# 9. Zugriff einrichten
./scripts/port-forward.sh

# 10. Browser öffnen
# http://localhost:3000 (WebUI)
# http://localhost:8000 (API)
```

## 🛠️ Deployment-Befehle

| Befehl | Beschreibung |
|--------|--------------|
| `./deploy-v100.sh` | Interaktives Deployment mit Menüführung (empfohlen) |
| `./scripts/deploy-tgi-v100.sh` | TGI mit V100-Optimierungen deployen |
| `./scripts/deploy-vllm-v100.sh` | vLLM mit V100-Optimierungen deployen |
| `./scripts/deploy-webui.sh` | Web-Benutzeroberfläche installieren |
| `./scripts/cleanup.sh` | Alle erstellten Ressourcen entfernen |

### Konfiguration

```bash
# IC-Login (bei erstem Zugriff)
./scripts/icc-login.sh

# Konfiguration anpassen
cp configs/config.v100.sh configs/config.sh
nano configs/config.sh
```

## 🔌 Zugriff und Monitoring

| Befehl | Beschreibung |
|--------|--------------|
| `./scripts/port-forward.sh` | Port-Forwarding für API und WebUI einrichten |
| `./scripts/port-forward.sh --api-port=9000` | Benutzerdefinierten API-Port verwenden |
| `./scripts/monitor-gpu.sh` | GPU-Auslastung in Echtzeit überwachen |
| `./scripts/monitor-gpu.sh -i 5 -f full` | Detailliertes GPU-Monitoring mit 5s-Intervall |
| `./scripts/check-logs.sh tgi` | Logs des TGI-Servers anzeigen |
| `./scripts/check-logs.sh webui` | Logs der WebUI anzeigen |
| `./scripts/check-logs.sh tgi -a` | TGI-Logs analysieren und Probleme identifizieren |
| `./scripts/test-gpu.sh` | GPU-Funktionalität testen |

## 🔄 Modell- und GPU-Verwaltung

### Modellwechsel

```bash
# Modell wechseln (Standard-Präzision)
./scripts/change-model.sh --model "microsoft/phi-2"

# Modell mit Quantisierung (für größere Modelle auf einer GPU)
./scripts/change-model.sh --model "mistralai/Mistral-7B-Instruct-v0.2" --quantization awq

# Modell mit angepassten Parametern
./scripts/change-model.sh --model "NousResearch/Hermes-3-Llama-3.1-8B" --max-len 2048 --temp 0.7
```

### GPU-Skalierung

```bash
# Auf 2 GPUs skalieren (für größere Modelle)
./scripts/scale-gpu.sh --count 2

# Auf 1 GPU zurücksetzen mit angepasstem Shared Memory
./scripts/scale-gpu.sh --count 1 --mem 8Gi

# Multi-GPU mit mehr Shared Memory für 13B+ Modelle
./scripts/scale-gpu.sh --count 4 --mem 16Gi
```

## 🔍 Fehlerbehebung

| Befehl | Beschreibung |
|--------|--------------|
| `./scripts/test-v100-compatibility.sh` | V100-GPU-Kompatibilität überprüfen |
| `./scripts/deploy-tgi-minimal.sh` | Minimales Test-Deployment mit TinyLlama starten |
| `kubectl -n $NAMESPACE describe pod -l app=llm-server` | Pod-Details für Fehlerdiagnose anzeigen |
| `kubectl -n $NAMESPACE get events` | Kubernetes-Events für Fehlermeldungen anzeigen |
| `./scripts/reset-and-test-tgi.sh` | TGI zurücksetzen und mit Minimal-Setup testen |

### Häufige Probleme und Lösungen

#### Out-of-Memory (OOM) Fehler

**Symptom:**
```
Shard process was signaled to shutdown with signal 9
```

**Lösungen:**
- Kleineres Modell: `./scripts/change-model.sh --model "microsoft/phi-2"`
- Quantisierung aktivieren: `./scripts/change-model.sh --model "mistralai/Mistral-7B-Instruct-v0.2" --quantization awq`
- Mehr GPUs: `./scripts/scale-gpu.sh --count 2`
- Kontextlänge reduzieren: In `config.sh` setzen: `export MAX_INPUT_LENGTH=1024` und `export MAX_TOTAL_TOKENS=2048`

#### Modell lädt nicht

**Lösungen:**
- Logs überprüfen: `./scripts/check-logs.sh tgi`
- Hugging Face Token in `config.sh` setzen
- TGI-Version überprüfen: `kubectl -n $NAMESPACE describe pod -l app=llm-server | grep Image`
- Minimales Deployment testen: `./scripts/deploy-tgi-minimal.sh`

## 📊 Modellempfehlungen für V100 GPUs

| Modellgröße | GPU-Setup | Quantisierung | Empfohlene Modelle |
|-------------|-----------|---------------|-------------------|
| 1-3B | 1× V100 (16GB) | Keine | microsoft/phi-2, google/gemma-2b |
| 7B | 1× V100 (16GB) | AWQ | Mistral-7B, Llama-2-7b |
| 7B | 2× V100 (32GB) | Keine | Mistral-7B, Llama-2-7b |
| 13B | 2× V100 (32GB) | AWQ | Llama-2-13b |
| 13B | 4× V100 (64GB) | Keine | Llama-2-13b |
| 34B+ | Nicht empfohlen | - | Für größere Modelle A100 GPUs verwenden |

## 📝 Beispiele

### Komplettes Setup mit TGI für Mistral-7B mit WebUI

```bash
# 1. Konfiguration anpassen
cp configs/config.v100.sh configs/config.sh
sed -i 's/wXYZ123-default/wABC123-default/' configs/config.sh  # Namespace anpassen
sed -i 's/MODEL_NAME=".*"/MODEL_NAME="mistralai\/Mistral-7B-Instruct-v0.2"/' configs/config.sh

# 2. TGI mit AWQ-Quantisierung deployen (für 1 GPU)
export QUANTIZATION="awq"
./scripts/deploy-tgi-v100.sh

# 3. WebUI installieren
./scripts/deploy-webui.sh

# 4. Zugriff einrichten
./scripts/port-forward.sh
```

### Multi-GPU Setup für Llama-2-13B

```bash
# 1. Konfiguration anpassen
cp configs/config.v100.sh configs/config.sh
# Namespace und Token anpassen
sed -i 's/wXYZ123-default/wABC123-default/' configs/config.sh
sed -i 's/HUGGINGFACE_TOKEN=""/HUGGINGFACE_TOKEN="hf_..."/' configs/config.sh
sed -i 's/MODEL_NAME=".*"/MODEL_NAME="meta-llama\/Llama-2-13b-chat-hf"/' configs/config.sh

# 2. Auf 2 GPUs skalieren
sed -i 's/GPU_COUNT=1/GPU_COUNT=2/' configs/config.sh

# 3. Shared Memory erhöhen
sed -i 's/DSHM_SIZE="8Gi"/DSHM_SIZE="16Gi"/' configs/config.sh

# 4. TGI Server deployen
./scripts/deploy-tgi-v100.sh

# 5. WebUI installieren
./scripts/deploy-webui.sh

# 6. Zugriff einrichten
./scripts/port-forward.sh
```

### vLLM Deployment mit TinyLlama für Tests

```bash
# 1. Konfiguration anpassen
cp configs/config.v100.sh configs/config.sh
sed -i 's/wXYZ123-default/wABC123-default/' configs/config.sh
sed -i 's/ENGINE_TYPE="tgi"/ENGINE_TYPE="vllm"/' configs/config.sh
sed -i 's/MODEL_NAME=".*"/MODEL_NAME="TinyLlama\/TinyLlama-1.1B-Chat-v1.0"/' configs/config.sh

# 2. vLLM deployen
./scripts/deploy-vllm-v100.sh

# 3. WebUI installieren
./scripts/deploy-webui.sh

# 4. Zugriff einrichten
./scripts/port-forward.sh
```

## 📈 Performance-Tipps

1. **Verwenden Sie AWQ-Quantisierung** für Modelle ≥7B auf einer einzelnen GPU
2. **Sharded Mode** (Multi-GPU) für Modelle ≥13B ohne Quantisierung
3. **Reduzieren Sie die Kontextlänge** bei Speicherproblemen
4. **Passen Sie CUDA_MEMORY_FRACTION** (0.8 bis 0.9) nach Bedarf an
5. **Verwenden Sie mehr dshm** (Shared Memory) bei Multi-GPU
6. **vLLM** kann bei einigen Modellen besser performen als TGI
7. **Testen Sie verschiedene BLOCK_SIZE-Werte** (8, 16, 32) in vLLM für optimale Performance

## 🔖 Weitere Informationen

- [V100-OPTIMIZATION.md](V100-OPTIMIZATION.md) - Detaillierte V100-spezifische Optimierungen
- [DOCUMENTATION.md](DOCUMENTATION.md) - Vollständige Projektdokumentation
- [Text Generation Inference](https://github.com/huggingface/text-generation-inference) - TGI-Dokumentation
- [vLLM](https://github.com/vllm-project/vllm) - vLLM-Dokumentation
