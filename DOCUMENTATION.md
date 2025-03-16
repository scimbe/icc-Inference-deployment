# Ausführliche Dokumentation: ICC LLM Deployment

Diese Dokumentation führt Sie durch den gesamten Prozess der Einrichtung und Bereitstellung von Text Generation Inference (TGI) oder vLLM mit Multi-GPU-Unterstützung auf der Informatik Compute Cloud (ICC) der HAW Hamburg.

## Inhaltsverzeichnis

1. [ICC-Zugang einrichten](#1-icc-zugang-einrichten)
2. [Repository klonen und konfigurieren](#2-repository-klonen-und-konfigurieren)
3. [Engine-Auswahl: TGI vs. vLLM](#3-engine-auswahl-tgi-vs-vllm)
4. [TGI mit GPU-Unterstützung deployen](#4-tgi-mit-gpu-unterstützung-deployen)
5. [vLLM mit GPU-Unterstützung deployen](#5-vllm-mit-gpu-unterstützung-deployen)
6. [Open WebUI für LLM-Zugriff einrichten](#6-open-webui-für-llm-zugriff-einrichten)
7. [Modelle herunterladen und verwenden](#7-modelle-herunterladen-und-verwenden)
8. [Auf den Dienst zugreifen](#8-auf-den-dienst-zugreifen)
9. [GPU-Ressourcen skalieren](#9-gpu-ressourcen-skalieren)
10. [GPU-Testen und Überwachen](#10-gpu-testen-und-überwachen)
11. [Fehlerbehebung](#11-fehlerbehebung)
12. [Weitere Performance-Optimierungen](#12-weitere-performance-optimierungen)
13. [Ressourcen bereinigen](#13-ressourcen-bereinigen)

## 1. ICC-Zugang einrichten

### Automatische Einrichtung (empfohlen)

Der einfachste Weg, um den ICC-Zugang einzurichten, ist unser Hilfsskript zu verwenden:

```bash
./scripts/icc-login.sh
```

Dieses Skript führt Sie durch den gesamten Prozess:
1. Öffnet die ICC-Login-Seite in Ihrem Standard-Browser
2. Führt Sie durch den Anmeldeprozess mit Ihrer infw-Kennung
3. Hilft beim Speichern und Einrichten der heruntergeladenen Kubeconfig-Datei
4. Testet die Verbindung und zeigt Ihre Namespace-Informationen an

### Manuelle Einrichtung

Falls Sie die manuelle Einrichtung bevorzugen:

1. Besuchen Sie das Anmeldeportal der ICC unter https://icc-login.informatik.haw-hamburg.de/
2. Authentifizieren Sie sich mit Ihrer infw-Kennung
3. Laden Sie die generierte Kubeconfig-Datei herunter
4. Platzieren Sie die Kubeconfig-Datei in Ihrem `~/.kube/` Verzeichnis

```bash
# Linux/macOS
mkdir -p ~/.kube
mv /pfad/zur/heruntergeladenen/config.txt ~/.kube/config

# Oder als Umgebungsvariable
export KUBECONFIG=/pfad/zur/heruntergeladenen/config.txt
```

### Überprüfen Sie Ihren Namespace

Die ICC erstellt automatisch einen Namespace basierend auf Ihrer w-Kennung (wenn Sie sich mit infwXYZ123 anmelden, ist Ihr Namespace wXYZ123-default).

```bash
kubectl get namespace
```

## 2. Repository klonen und konfigurieren

```bash
# Repository klonen
git clone https://github.com/scimbe/icc-llm-deployment.git
cd icc-llm-deployment

# Konfigurationsdatei erstellen
cp configs/config.v100.sh configs/config.sh
```

Öffnen Sie `configs/config.sh` und passen Sie die Variablen an Ihre Umgebung an:

```bash
# Beispielkonfiguration
NAMESPACE="wXYZ123-default"  # Ersetzen Sie dies mit Ihrem Namespace
ENGINE_TYPE="tgi"            # "tgi" oder "vllm" je nach Präferenz
TGI_DEPLOYMENT_NAME="my-tgi"
TGI_SERVICE_NAME="my-tgi"
VLLM_DEPLOYMENT_NAME="my-vllm"
VLLM_SERVICE_NAME="my-vllm"
WEBUI_DEPLOYMENT_NAME="llm-webui"
WEBUI_SERVICE_NAME="llm-webui"
USE_GPU=true                 # Auf false setzen, wenn keine GPU benötigt wird
GPU_TYPE="gpu-tesla-v100"    # Oder "gpu-tesla-v100s" je nach Verfügbarkeit
GPU_COUNT=1                  # Anzahl der GPUs (üblicherweise 1, kann bis zu 4 sein)
MODEL_NAME="TheBloke/Mistral-7B-Instruct-v0.2-GPTQ"  # Das zu ladende Modell
QUANTIZATION="gptq"          # Optional: "awq" oder "gptq" für quantisierte Modelle
MAX_MODEL_LEN=4096           # Maximale Kontext-Länge
```

## 3. Engine-Auswahl: TGI vs. vLLM

Bevor Sie mit dem Deployment beginnen, sollten Sie sich für eine Inference-Engine entscheiden. Hier ein Vergleich:

### Text Generation Inference (TGI)

**Vorteile:**
- Stabile Performance auf V100-GPUs
- Gut dokumentiert und weit verbreitet
- Einfache Konfiguration
- Hervorragende MoE-Modell-Unterstützung (z.B. Mixtral)
- Optimiert für einzelne Anfragen mit niedriger Latenz

**Nachteile:**
- Weniger optimierte Speichernutzung als vLLM
- Multi-GPU über Sharded-Modus, nicht so flexibel wie Tensor-Parallelismus

### vLLM

**Vorteile:**
- Höherer Durchsatz bei mehreren gleichzeitigen Anfragen
- PagedAttention für effizientere Speichernutzung
- Tensor-Parallelismus für Multi-GPU-Szenarien
- Bessere Unterstützung für GPTQ-quantisierte Modelle

**Nachteile:**
- Einige Parameter-Kompatibilitätsprobleme bei neueren Versionen
- Kann mehr Konfiguration für optimale Performance erfordern

### Empfehlungen

- **TGI** für: Einfache Setups, MoE-Modelle (Mixtral), stabile Multi-User-Umgebungen
- **vLLM** für: Höchstmöglichen Durchsatz, optimale Speichernutzung, GPTQ-quantisierte Modelle

Die Auswahl der Engine erfolgt durch Setzen von `ENGINE_TYPE="tgi"` oder `ENGINE_TYPE="vllm"` in Ihrer `config.sh`. Sie können im interaktiven Modus mit `./deploy-v100.sh` auch zwischen den Engines wechseln.

## 4. TGI mit GPU-Unterstützung deployen

Nachdem Sie Ihre Konfiguration angepasst haben, können Sie das TGI-Deployment starten:

```bash
./scripts/deploy-tgi-v100.sh
```

Dieser Befehl:
1. Erstellt das Kubernetes Deployment mit GPU-Unterstützung
2. Konfiguriert TGI mit den angegebenen Parametern (inkl. Multi-GPU, wenn gewünscht)
3. Erstellt einen Kubernetes Service für den Zugriff auf TGI
4. Wartet, bis die Pods erfolgreich gestartet sind

Der TGI-Server läuft als OpenAI-kompatibler API-Endpunkt auf Port 8000 innerhalb des Clusters.

### Parameter für TGI

TGI bietet zahlreiche Konfigurationsoptionen, die wichtigsten sind:

- `--sharded`: Aktiviert den Sharded-Modus für Multi-GPU-Nutzung
- `--num-shard`: Anzahl der Shards (entspricht der GPU-Anzahl)
- `--max-parallel-loading-workers`: Optimiert paralleles Laden für Multi-GPU-Setups
- `--dtype`: Genauigkeit der Modellberechnung (float16, bfloat16, etc.)
- `--quantize`: Speichersparende Quantisierung (awq, gptq, etc.)
- `--max-input-length`: Maximale Eingabelänge
- `--max-total-tokens`: Maximale Gesamtanzahl von Tokens (Eingabe + Ausgabe)

Diese Parameter können in der `config.sh` angepasst werden.

## 5. vLLM mit GPU-Unterstützung deployen

Wenn Sie vLLM anstelle von TGI verwenden möchten, können Sie das vLLM-Deployment wie folgt starten:

```bash
./scripts/deploy-vllm-v100.sh
```

Dieser Befehl:
1. Erstellt das Kubernetes Deployment für vLLM mit GPU-Unterstützung
2. Konfiguriert vLLM optimiert für V100-GPUs
3. Erstellt einen Kubernetes Service für den Zugriff auf vLLM
4. Wartet, bis die Pods erfolgreich gestartet sind

Der vLLM-Server stellt ebenfalls eine OpenAI-kompatible API auf Port 8000 innerhalb des Clusters bereit.

### Parameter für vLLM

vLLM bietet folgende wichtige Konfigurationsoptionen:

- `--tensor-parallel-size`: Anzahl der GPUs für parallele Modellverarbeitung
- `--block-size`: Block-Größe für PagedAttention (8, 16 oder 32)
- `--swap-space`: Swap-Space in GB für mehr verfügbaren Speicher
- `--max-model-len`: Maximale Kontextlänge
- `--quantization`: Quantisierungsmethode (awq, gptq)

Diese Parameter können in der `config.sh` angepasst werden und werden automatisch von den Deployment-Skripten verwendet.

### NCCL-Konfiguration für Multi-GPU

Sowohl TGI als auch vLLM verwenden NCCL für die GPU-zu-GPU-Kommunikation. Die folgenden Umgebungsvariablen sind in der Konfiguration enthalten:

```bash
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=ALL
export NCCL_P2P_DISABLE=0
export NCCL_IB_DISABLE=0
export NCCL_P2P_LEVEL=NVL
export NCCL_SOCKET_IFNAME="^lo,docker"
export NCCL_SHM_DISABLE=0
```

Diese Variablen optimieren die Multi-GPU-Kommunikation speziell für die V100-Umgebung.

## 6. Open WebUI für LLM-Zugriff einrichten

Open WebUI ist eine benutzerfreundliche Weboberfläche, die mit TGI oder vLLM über die OpenAI-kompatible API kommuniziert:

```bash
./scripts/deploy-webui.sh
```

Die WebUI wird so konfiguriert, dass sie sich automatisch mit dem LLM-Server verbindet und kommuniziert über die internen Kubernetes-Services.

## 7. Modelle herunterladen und verwenden

Sowohl TGI als auch vLLM unterstützen zahlreiche Modelle von HuggingFace. Der Server lädt das Modell automatisch beim Start, basierend auf dem konfigurierten `MODEL_NAME`.

Um das Modell zu ändern:

```bash
# Ändern Sie das Modell und starten Sie das Deployment neu
./scripts/change-model.sh --model "TheBloke/Mistral-7B-Instruct-v0.2-GPTQ" --quantization gptq
```

Beachten Sie, dass beim Wechsel des Modells der Server-Pod neu gestartet wird und je nach Modellgröße und Internetgeschwindigkeit kann der Download einige Zeit in Anspruch nehmen.

### Modellempfehlungen

Je nach verfügbarem GPU-Speicher und Anzahl der GPUs, können Sie verschiedene Modellgrößen verwenden:

| Modellgröße | GPU-Speicherbedarf (16-bit) | Empfohlene GPU-Konfiguration | Quantisierung |
|-------------|-----------------------------|------------------------------|---------------|
| 2-3B        | ~5 GB                      | 1 Tesla V100 (16GB)          | Keine         |
| 7B          | ~14 GB                      | 1 Tesla V100 (16GB)          | AWQ/GPTQ      |
| 7B          | ~14 GB                      | 2 Tesla V100 (32GB gesamt)   | Keine         |
| 13B         | ~26 GB                      | 2 Tesla V100 (32GB gesamt)   | AWQ/GPTQ      |
| 13B         | ~26 GB                      | 4 Tesla V100 (64GB gesamt)   | Keine         |
| 70B         | ~140 GB                     | Nicht empfohlen für V100     | -             |

Mit Quantisierung (AWQ/GPTQ) können Sie den Speicherbedarf um etwa 50-75% reduzieren, was größere Modelle auch auf weniger GPUs ermöglicht.

### Empfohlene Modelle

**Für TGI:**
- Microsoft Phi-2: `microsoft/phi-2` (3B Parameter)
- Mistral 7B: `mistralai/Mistral-7B-Instruct-v0.2` (Standard)
- Mistral 7B mit AWQ: `TheBloke/Mistral-7B-Instruct-v0.2-AWQ` (Quantisiert)
- Llama-2 13B: `meta-llama/Llama-2-13b-chat-hf` (Benötigt HF-Token)

**Für vLLM:**
- Gemma 2B: `google/gemma-2b-it` (2B Parameter) 
- Mistral 7B mit GPTQ: `TheBloke/Mistral-7B-Instruct-v0.2-GPTQ` (Empfohlen)
- Mixtral 8x7B mit GPTQ: `TheBloke/Mixtral-8x7B-Instruct-v0.1-GPTQ` (MoE-Modell)
- Llama-2 13B mit GPTQ: `TheBloke/Llama-2-13b-chat-GPTQ` (Quantisiert)

## 8. Auf den Dienst zugreifen

Nach dem erfolgreichen Deployment können Sie auf die Dienste zugreifen:

```bash
# Für LLM API und WebUI gleichzeitig (empfohlen)
./scripts/port-forward.sh

# Oder manuell für einzelne Dienste
kubectl -n $NAMESPACE port-forward svc/$TGI_SERVICE_NAME 8000:8000
# oder
kubectl -n $NAMESPACE port-forward svc/$VLLM_SERVICE_NAME 8000:8000
# und
kubectl -n $NAMESPACE port-forward svc/$WEBUI_SERVICE_NAME 3000:3000
```

Anschließend können Sie die WebUI unter http://localhost:3000 in Ihrem Browser öffnen und die API ist unter http://localhost:8000 verfügbar.

### API-Verwendung

Sowohl TGI als auch vLLM implementieren die OpenAI-kompatible API, die Sie direkt ansprechen können:

```bash
# Beispiel: Chat-Completion über die API abfragen
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "TheBloke/Mistral-7B-Instruct-v0.2-GPTQ",
    "messages": [{"role": "user", "content": "Was ist die HAW Hamburg?"}],
    "temperature": 0.7
  }'
```

## 9. GPU-Ressourcen skalieren

Je nach Anforderung können Sie die Anzahl der verwendeten GPUs für das Deployment dynamisch anpassen:

```bash
# Skalieren auf 2 GPUs
./scripts/scale-gpu.sh --count 2

# Zurück auf 1 GPU reduzieren
./scripts/scale-gpu.sh --count 1

# Skalieren mit angepasstem Shared Memory
./scripts/scale-gpu.sh --count 2 --mem 16Gi
```

Das Skript führt folgende Aktionen aus:
1. Validiert die angeforderte GPU-Anzahl
2. Aktualisiert das Deployment mit der neuen GPU-Anzahl
3. Aktiviert/deaktiviert entsprechende Parallelisierungsparameter:
   - Für TGI: Sharded-Modus und num-shard Parameter
   - Für vLLM: Tensor-Parallelismus
4. Wartet auf das erfolgreiche Rollout

Beachten Sie, dass diese Änderung einen Neustart des Server-Pods verursacht und das Modell neu geladen werden muss.

### Multi-GPU-Spezifika

#### TGI Multi-GPU (Sharded-Modus)

- Verwendet `--sharded=true` und `--num-shard=<GPU_COUNT>`
- Shared Memory (dshm) wird automatisch erhöht: `8Gi × GPU_COUNT`
- `--max-parallel-loading-workers` wird optimiert für paralleles Laden

#### vLLM Multi-GPU (Tensor-Parallelismus)

- Verwendet `--tensor-parallel-size=<GPU_COUNT>`
- NCCL-Konfiguration wichtig für effiziente Inter-GPU-Kommunikation
- Shared Memory wird ebenfalls entsprechend angepasst

### Wichtige Hinweise zur GPU-Skalierung

- Die maximale Anzahl von GPUs ist durch die ICC-Ressourcenbeschränkungen und die Verfügbarkeit limitiert
- Alle GPUs müssen auf demselben Knoten sein, Node-übergreifendes Sharding wird nicht unterstützt
- Bei Verwendung mehrerer GPUs sollte das Shared Memory erhöht werden (passiert automatisch)

## 10. GPU-Testen und Überwachen

Das Projekt bietet mehrere Skripte für Tests, Überwachung und Benchmarking der GPU-Funktionalität.

### GPU-Funktionalität testen

```bash
./scripts/test-gpu.sh
```

Dieses Skript führt folgende Tests durch:
- Prüft die NVIDIA GPU-Verfügbarkeit mit `nvidia-smi`
- Überprüft CUDA-Umgebungsvariablen
- Testet die LLM API

### GPU-Leistung überwachen

```bash
# GPU-Monitoring mit TUI (Terminal User Interface)
./scripts/monitor-gpu.sh

# Performance mit spezifischen Parametern messen
./scripts/monitor-gpu.sh -i 5 -f full -s metrics.csv
```

### Minimaltests für Troubleshooting

Für Fehlerbehebung können Sie minimale Deployments mit reduzierten Anforderungen starten:

```bash
# Minimales TGI-Deployment
./scripts/deploy-tgi-minimal.sh

# Minimales vLLM-Deployment
./scripts/deploy-vllm-minimal.sh
```

Diese Skripte verwenden ein sehr kleines Modell (TinyLlama) und minimale Ressourcenanforderungen, um die grundlegende Funktionalität zu testen.

## 11. Fehlerbehebung

### Allgemeine Probleme

Wenn Sie Probleme mit dem Deployment haben, prüfen Sie zunächst die Logs:

```bash
# TGI-Logs anzeigen
./scripts/check-logs.sh tgi

# vLLM-Logs anzeigen
./scripts/check-logs.sh vllm

# WebUI-Logs anzeigen
./scripts/check-logs.sh webui
```

### Häufige Probleme und Lösungen

1. **Pod bleibt hängen im Pending-Status**:
   - Überprüfen Sie, ob genügend GPU-Ressourcen verfügbar sind: `kubectl get nodes -o=custom-columns=NODE:.metadata.name,GPU:.status.capacity.'nvidia\.com/gpu'`
   - Prüfen Sie die Beschreibung des Pods: `kubectl -n $NAMESPACE describe pod $POD_NAME`

2. **Server startet nicht wegen Out of Memory**:
   - Wechseln Sie zu einem kleineren Modell oder erhöhen Sie die Anzahl der GPUs
   - Verwenden Sie Quantisierung mit `--quantize awq` oder `--quantize gptq`
   - Reduzieren Sie die Kontextlänge in der Konfiguration

3. **WebUI kann keine Verbindung zum LLM-Server herstellen**:
   - Überprüfen Sie, ob der Server-Service läuft: `kubectl -n $NAMESPACE get svc $TGI_SERVICE_NAME` oder `kubectl -n $NAMESPACE get svc $VLLM_SERVICE_NAME`
   - Testen Sie die API direkt: `kubectl -n $NAMESPACE port-forward svc/$TGI_SERVICE_NAME 8000:8000` und dann `curl http://localhost:8000/v1/models`

4. **vLLM Parameter-Kompatibilitätsprobleme**:
   - Bei Fehlern wie `unrecognized arguments: --max-batch-size 32`, prüfen Sie die vLLM-Version
   - Die Deployment-Skripte erkennen automatisch nicht unterstützte Parameter und überspringen sie
   - Sie können problematische Parameter in der Konfiguration auskommentieren

5. **NCCL-Kommunikationsprobleme bei Multi-GPU**:
   - Prüfen Sie die NCCL-Konfiguration und passen Sie sie ggf. an
   - Bei anhaltenden Problemen setzen Sie `NCCL_P2P_DISABLE=1` und `NCCL_IB_DISABLE=1`

Eine umfassendere Anleitung zur Fehlerbehebung finden Sie in [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## 12. Weitere Performance-Optimierungen

### Shared Memory (IPC) optimieren

Für Multi-GPU-Anwendungen ist es wichtig, ausreichend Shared Memory bereitzustellen. Das Deployment-Skript passt die Größe automatisch an die GPU-Anzahl an:

```yaml
volumes:
- name: dshm
  emptyDir:
    medium: Memory
    sizeLimit: <8Gi × GPU_COUNT>  # Skaliert mit der GPU-Anzahl
```

### Quantisierung verwenden

Für große Modelle empfehlen wir die Verwendung von Quantisierung:

```bash
# Aktivieren Sie GPTQ-Quantisierung (empfohlen für vLLM)
./scripts/change-model.sh --model "TheBloke/Mistral-7B-Instruct-v0.2-GPTQ" --quantization "gptq"

# Aktivieren Sie AWQ-Quantisierung (empfohlen für TGI)
./scripts/change-model.sh --model "TheBloke/Mistral-7B-Instruct-v0.2-AWQ" --quantization "awq"
```

### Engine-spezifische Optimierungen

#### TGI-Optimierungen

- Verwenden Sie `--max-concurrent-requests` basierend auf der GPU-Anzahl
- Stellen Sie `--cuda-memory-fraction` auf 0.85 für V100-GPUs
- Verwenden Sie `--max-parallel-loading-workers` gleich der GPU-Anzahl

#### vLLM-Optimierungen

- Experimentieren Sie mit verschiedenen `--block-size`-Werten (8, 16, 32)
- Aktivieren Sie `--swap-space` für mehr verfügbaren Speicher
- Optimieren Sie `--tensor-parallel-size` entsprechend der GPU-Anzahl

## 13. Ressourcen bereinigen

Wenn Sie die Deployment entfernen möchten:

```bash
./scripts/cleanup.sh
```

Oder einzelne Komponenten:

```bash
kubectl -n $NAMESPACE delete deployment $TGI_DEPLOYMENT_NAME
kubectl -n $NAMESPACE delete service $TGI_SERVICE_NAME
# oder
kubectl -n $NAMESPACE delete deployment $VLLM_DEPLOYMENT_NAME
kubectl -n $NAMESPACE delete service $VLLM_SERVICE_NAME
# und
kubectl -n $NAMESPACE delete deployment $WEBUI_DEPLOYMENT_NAME
kubectl -n $NAMESPACE delete service $WEBUI_SERVICE_NAME
```