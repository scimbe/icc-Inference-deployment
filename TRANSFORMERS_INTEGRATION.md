# Transformers-Integration für TGI und Open WebUI

Diese Dokumentation beschreibt, wie Sie die erweiterte Hugging Face Transformers-Bibliothek mit Text Generation Inference (TGI) und Open WebUI auf der ICC der HAW Hamburg verwenden können.

## Überblick

Die Integration von huggingface/transformers in Ihr TGI-Deployment bietet folgende Vorteile:

- **Erweiterte Modellkonfiguration**: Umfangreiche Anpassungsmöglichkeiten in der WebUI
- **Verbesserte Tokenisierung**: Optimierte Performance durch `TOKENIZERS_PARALLELISM`
- **Remote-Code-Unterstützung**: Integration komplexer Modelle mit `TRUST_REMOTE_CODE`
- **PEFT-Adapter**: Möglichkeit, Parameter-Efficient Fine-Tuning zu verwenden
- **Erweiterte WebUI-Funktionen**: Modellparameter direkt in der Benutzeroberfläche anpassen

## Schnellstart

Verwenden Sie das spezielle Deployment-Skript, um TGI mit Transformers-Integration zu starten:

```bash
# Setze Ausführungsberechtigungen
chmod +x deploy-with-transformers.sh

# Starte Deployment
./deploy-with-transformers.sh
```

## Konfiguration

Die Transformers-Integration wird durch die Datei `configs/config.transformers.sh` konfiguriert:

```bash
# Kopiere die vorgefertigte Konfiguration
cp configs/config.transformers.sh configs/config.sh

# Passe die Konfiguration an deine Umgebung an
vim configs/config.sh
```

### Wichtige Konfigurationsparameter

| Parameter | Beschreibung | Standardwert |
|-----------|--------------|--------------|
| `ENABLE_TRANSFORMERS` | Aktiviert die Transformers-Integration | `true` |
| `TRUST_REMOTE_CODE` | Erlaubt Ausführung vom Modell-Code | `true` |
| `TOKENIZERS_PARALLELISM` | Beschleunigt die Tokenisierung | `true` |
| `TRANSFORMERS_CACHE` | Cache-Pfad für Transformers | `/data/transformers-cache` |
| `MAX_BATCH_SIZE` | Maximale Batch-Größe für Inferenz | `8` |
| `PEFT_ADAPTER_ID` | Optional: Pfad zum PEFT-Adapter | - |

## Deployment

Die Integration verwendet angepasste Deployment-Skripte:

1. **TGI mit Transformers-Unterstützung**: `scripts/deploy-tgi-transformers.sh`
2. **WebUI mit Transformers-Integration**: `scripts/deploy-webui-transformers.sh`

Bei Verwendung des Hauptskripts werden diese Skripte automatisch ausgeführt.

## Features

### 1. Erweiterte Modellkonfiguration

Über die WebUI-Einstellungen können folgende Parameter angepasst werden:

- **Temperatur**: Kontrolliert die Zufälligkeit der Ausgabe (0.0-1.0)
- **Top-p**: Sampling-Parameter für die Tokenauswahl
- **Top-k**: Anzahl der wahrscheinlichsten Tokens für das Sampling
- **Presence/Frequency Penalty**: Vermeidet Wiederholungen
- **Max Tokens**: Maximale Ausgabelänge

### 2. PEFT-Adapter-Unterstützung

PEFT (Parameter-Efficient Fine-Tuning) ermöglicht das Feintuning großer Modelle mit begrenzten Ressourcen:

```bash
# Konfiguriere einen PEFT-Adapter in config.sh
export PEFT_ADAPTER_ID="pfad/zu/adapter"
```

### 3. Benutzerdefinierte Modellkonfiguration

Sie können zusätzliche Transformers-Konfigurationen über einen JSON-String definieren:

```bash
# Beispiel für erweiterte Konfiguration
export TRANSFORMERS_EXTRA_CONFIG='{"use_cache":true,"attn_implementation":"flash_attention_2"}'
```

## Performance-Optimierung

Für optimale Performance mit Transformers:

1. **Ausreichend Speicher bereitstellen**: Erhöhen Sie `MEMORY_LIMIT` in config.sh
2. **Cache-Nutzung optimieren**: Persistente Volumes für TRANSFORMERS_CACHE
3. **Tokenisierung beschleunigen**: TOKENIZERS_PARALLELISM=true verwenden
4. **GPU-Nutzung optimieren**: Bei größeren Modellen mehrere GPUs verwenden

## Fehlerbehebung

### Häufige Probleme und Lösungen

1. **WebUI zeigt keine erweiterten Parameter**:
   ```bash
   # Prüfe, ob Transformers aktiviert ist
   kubectl -n $NAMESPACE exec -it $POD_NAME -- env | grep TRANSFORMERS
   # Neustart der WebUI, falls nötig
   kubectl -n $NAMESPACE delete pod $POD_NAME
   ```

2. **Modell lädt nicht mit Transformers**:
   ```bash
   # Überprüfe die Logs auf spezifische Fehler
   kubectl -n $NAMESPACE logs deployment/$TGI_DEPLOYMENT_NAME
   # Versuche, TRUST_REMOTE_CODE zu deaktivieren falls Probleme auftreten
   ```

3. **Out-of-Memory bei großen Modellen**:
   ```bash
   # Erhöhe die Ressourcenlimits
   export MEMORY_LIMIT="16Gi"
   # Verwende Quantisierung
   export QUANTIZATION="awq"
   ```

## Weiterführende Links

- [Hugging Face Transformers Dokumentation](https://huggingface.co/docs/transformers)
- [Text Generation Inference Repository](https://github.com/huggingface/text-generation-inference)
- [Open WebUI Dokumentation](https://github.com/open-webui/open-webui)
