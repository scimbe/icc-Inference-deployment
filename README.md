# IC-LLM: V100-optimiertes LLM-Deployment System

Eine umfassende Lösung für das Deployment von Large Language Models (LLMs) auf NVIDIA Tesla V100 GPUs in der HAW Hamburg Informatik Compute Cloud (ICC).

<div align="center">
  <img src="https://huggingface.co/datasets/huggingface/documentation-images/resolve/main/TGI.png" alt="LLM Deployment" width="600px">
</div>

## 🌟 Hauptfeatures

- **V100-optimierte Konfiguration** für NVIDIA Tesla V100 GPUs
- **Zwei Inference-Engines**: Text Generation Inference (TGI) und vLLM
- **Multi-GPU-Unterstützung** mit bis zu 4x V100 GPUs im Sharded-Modus
- **OpenAI-kompatible REST API** für einfache Integration
- **Benutzerfreundliche WebUI** für Chat-Interaktionen
- **Unterstützung für zahlreiche Modelle**: Mistral, Llama, Gemma, Phi, etc.
- **Speicheroptimierungen**: AWQ Quantisierung, optimierte Kontextlängen

## 📋 Voraussetzungen

- HAW Hamburg infw-Account mit ICC-Zugang
- kubectl-Client auf Ihrem lokalen System
- VPN-Verbindung zum HAW-Netz (bei Remote-Zugriff)

## 🚀 Schnellstart

```bash
# Repository klonen
git clone https://github.com/scimbe/icc-Inference-deployment.git
cd icc-Inference-deployment

# Berechtigung setzen
chmod +x scripts/*.sh
chmod +x *.sh

# ICC-Login durchführen (einmalig)
./scripts/icc-login.sh

# Deployment starten (interaktiver Modus)
./deploy-v100.sh
```

Nach dem Deployment können Sie die WebUI unter http://localhost:3000 und die API unter http://localhost:8000 erreichen.

## 🖥️ Manuelle Installation

```bash
# 1. V100-optimierte Konfiguration kopieren
cp configs/config.v100.sh configs/config.sh

# 2. Konfiguration anpassen (wichtig!)
#    - NAMESPACE auf Ihre w-Kennung + "-default" setzen
#    - Modell und GPU-Anzahl wählen
nano configs/config.sh

# 3. TGI mit V100-Optimierungen deployen
./scripts/deploy-tgi-v100.sh

# 4. ODER: vLLM deployen
./scripts/deploy-vllm-v100.sh

# 5. Web-Oberfläche installieren
./scripts/deploy-webui.sh

# 6. Zugriff einrichten
./scripts/port-forward.sh
```

## 📊 Unterstützte Modelle und Anforderungen

| Modellgröße | GPU-Setup | Empfohlene Konfiguration | Beispielmodelle |
|-------------|-----------|--------------------------|-----------------|
| 2-3B | 1× V100 | Standard (float16) | microsoft/phi-2, google/gemma-2b |
| 7B | 1× V100 | AWQ Quantisierung | Mistral-7B-Instruct, Llama-2-7b-chat |
| 7B | 2× V100 | Sharded Mode | Mistral-7B-Instruct, Llama-2-7b-chat |
| 13B | 2× V100 | AWQ + Sharded | Llama-2-13b-chat |
| 13B | 4× V100 | Sharded Mode | Llama-2-13b-chat |

## 🔧 Wichtige Befehle

```bash
# Modellwechsel
./scripts/change-model.sh --model "mistralai/Mistral-7B-Instruct-v0.2" --quantization awq

# Skalierung auf mehrere GPUs
./scripts/scale-gpu.sh --count 2 --mem 16Gi

# Überwachung
./scripts/monitor-gpu.sh            # GPU-Nutzung überwachen
./scripts/check-logs.sh tgi -a      # Logs analysieren
./scripts/test-gpu.sh               # GPU-Funktionalität testen

# Fehlerbehebung
./scripts/test-v100-compatibility.sh  # V100-Kompatibilität testen
./scripts/deploy-tgi-minimal.sh       # Minimales Testdeployment
```

Eine vollständige Befehlsreferenz finden Sie in [COMMANDS.md](COMMANDS.md).

## 📁 Projektstruktur

```
icc-Inference-deployment/
├── configs/                # Konfigurationen
│   ├── config.v100.sh      # V100-optimierte Konfiguration
│   └── config.example.sh   # Beispielkonfiguration
├── scripts/                # Deployment- und Verwaltungsskripte
│   ├── deploy-tgi-v100.sh  # TGI V100-Deployment
│   ├── deploy-vllm-v100.sh # vLLM V100-Deployment
│   ├── deploy-webui.sh     # WebUI-Deployment
│   ├── port-forward.sh     # Port-Forwarding-Skript
│   └── ...                 # Weitere Hilfsskripte
├── deploy-v100.sh          # Hauptdeployment-Skript (interaktiv)
├── COMMANDS.md             # Befehlsreferenz
├── V100-OPTIMIZATION.md    # V100-spezifische Optimierungen
└── README.md               # Diese Dokumentation
```

## 🛠️ Fehlerbehebung

Bei Problemen helfen folgende Schritte:

1. **Logs prüfen**: `./scripts/check-logs.sh tgi -a`
2. **GPU-Test**: `./scripts/test-gpu.sh`
3. **Minimaltest**: `./scripts/deploy-tgi-minimal.sh`
4. **Pod-Beschreibung**: `kubectl -n $NAMESPACE describe pod -l app=llm-server`

Typische Probleme und detaillierte Lösungen finden Sie in [COMMANDS.md](COMMANDS.md#fehlerbehebung).

## 📝 Dokumentation

- [COMMANDS.md](COMMANDS.md) - Vollständige Befehlsreferenz mit Beispielen
- [V100-OPTIMIZATION.md](V100-OPTIMIZATION.md) - Detaillierte V100-Optimierungen
- [DOCUMENTATION.md](DOCUMENTATION.md) - Ausführliche technische Dokumentation

## 📄 Lizenz

Dieses Projekt steht unter der [MIT-Lizenz](LICENSE).

## 🙏 Danksagungen

- [Hugging Face Text Generation Inference](https://github.com/huggingface/text-generation-inference)
- [vLLM Project](https://github.com/vllm-project/vllm)
- [Open WebUI](https://github.com/open-webui/open-webui)
- HAW Hamburg Informatik Compute Cloud (ICC) Team
