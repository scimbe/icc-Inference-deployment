# Ausführliche Dokumentation: ICC TGI Deployment

Diese Dokumentation führt Sie durch den gesamten Prozess der Einrichtung und Bereitstellung von Text Generation Inference (TGI) mit Multi-GPU-Unterstützung auf der Informatik Compute Cloud (ICC) der HAW Hamburg.

## Inhaltsverzeichnis

1. [ICC-Zugang einrichten](#1-icc-zugang-einrichten)
2. [Repository klonen und konfigurieren](#2-repository-klonen-und-konfigurieren)
3. [TGI mit GPU-Unterstützung deployen](#3-tgi-mit-gpu-unterstützung-deployen)
4. [Open WebUI für TGI einrichten](#4-open-webui-für-tgi-einrichten)
5. [Modelle herunterladen und verwenden](#5-modelle-herunterladen-und-verwenden)
6. [Auf den Dienst zugreifen](#6-auf-den-dienst-zugreifen)
7. [GPU-Ressourcen skalieren](#7-gpu-ressourcen-skalieren)
8. [GPU-Testen und Überwachen](#8-gpu-testen-und-überwachen)
9. [Fehlerbehebung](#9-fehlerbehebung)
10. [Weitere Performance-Optimierungen](#10-weitere-performance-optimierungen)
11. [Ressourcen bereinigen](#11-ressourcen-bereinigen)

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
git clone https://github.com/scimbe/icc-tgi-deployment.git
cd icc-tgi-deployment

# Konfigurationsdatei erstellen
cp configs/config.example.sh configs/config.sh
```

Öffnen Sie `configs/config.sh` und passen Sie die Variablen an Ihre Umgebung an:

```bash
# Beispielkonfiguration
NAMESPACE="wXYZ123-default"  # Ersetzen Sie dies mit Ihrem Namespace
TGI_DEPLOYMENT_NAME="my-tgi"
TGI_SERVICE_NAME="my-tgi"
WEBUI_DEPLOYMENT_NAME="tgi-webui"
WEBUI_SERVICE_NAME="tgi-webui"
USE_GPU=true  # Auf false setzen, wenn keine GPU benötigt wird
GPU_TYPE="gpu-tesla-v100"  # Oder "gpu-tesla-v100s" je nach Verfügbarkeit
GPU_COUNT=1  # Anzahl der GPUs (üblicherweise 1, kann bis zu 4 sein)
MODEL_NAME="meta-llama/Llama-2-7b-chat-hf"  # Das zu ladende Modell
QUANTIZATION=""  # Optional: "awq" oder "gptq" für quantisierte Modelle
MAX_MODEL_LEN=4096  # Maximale Kontext-Länge
```

## 3. TGI mit GPU-Unterstützung deployen

Nachdem Sie Ihre Konfiguration angepasst haben, können Sie das Deployment starten:

```bash
./scripts/deploy-tgi.sh
```

Dieser Befehl:
1. Erstellt das Kubernetes Deployment mit GPU-Unterstützung
2. Konfiguriert TGI mit den angegebenen Parametern (inkl. Multi-GPU, wenn gewünscht)
3. Erstellt einen Kubernetes Service für den Zugriff auf TGI
4. Wartet, bis die Pods erfolgreich gestartet sind

Der TGI-Server läuft als OpenAI-kompatibler API-Endpunkt auf Port 3333 innerhalb des Clusters.

### Parameter für TGI

TGI bietet zahlreiche Konfigurationsoptionen, die wichtigsten sind:

- `--sharded`: Aktiviert den Sharded-Modus für Multi-GPU-Nutzung
- `--dtype`: Genauigkeit der Modellberechnung (float16, bfloat16, etc.)
- `--quantize`: Speichersparende Quantisierung (awq, gptq, etc.)
- `--max-input-length`: Maximale Eingabelänge
- `--max-total-tokens`: Maximale Gesamtanzahl von Tokens (Eingabe + Ausgabe)

Diese Parameter können in der `config.sh` angepasst werden.

## 4. Open WebUI für TGI einrichten

Open WebUI ist eine benutzerfreundliche Weboberfläche, die mit TGI über die OpenAI-kompatible API kommuniziert:

```bash
./scripts/deploy-webui.sh
```

Die WebUI wird so konfiguriert, dass sie sich automatisch mit dem TGI-Server verbindet und kommuniziert über die internen Kubernetes-Services.

## 5. Modelle herunterladen und verwenden

TGI unterstützt zahlreiche Modelle von HuggingFace. Der Server lädt das Modell automatisch beim Start, basierend auf dem konfigurierten `MODEL_NAME`.

Um das Modell zu ändern:

```bash
# Ändern Sie das Modell und starten Sie das Deployment neu
./scripts/change-model.sh --model "google/gemma-7b-it"
```

Beachten Sie, dass beim Wechsel des Modells der TGI-Pod neu gestartet wird und je nach Modellgröße und Internetgeschwindigkeit kann der Download einige Zeit in Anspruch nehmen.

### Modellempfehlungen

Je nach verfügbarem GPU-Speicher und Anzahl der GPUs, können Sie verschiedene Modellgrößen verwenden:

| Modellgröße | GPU-Speicherbedarf (16-bit) | Empfohlene GPU-Konfiguration |
|-------------|-----------------------------|------------------------------|
| 7B          | ~14 GB                      | 1 Tesla V100 (16GB)          |
| 13B         | ~26 GB                      | 2 Tesla V100 (32GB gesamt)   |
| 34B         | ~68 GB                      | 4 Tesla V100 (64GB gesamt)   |
| 70B         | ~140 GB                     | Nicht empfohlen für V100     |

Mit Quantisierung (AWQ/GPTQ) können Sie den Speicherbedarf um etwa 50-75% reduzieren, was größere Modelle auch auf weniger GPUs ermöglicht.

## 6. Auf den Dienst zugreifen

Nach dem erfolgreichen Deployment können Sie auf die Dienste zugreifen:

```bash
# Für TGI API und WebUI gleichzeitig (empfohlen)
./scripts/port-forward.sh

# Oder manuell für einzelne Dienste
kubectl -n $NAMESPACE port-forward svc/$TGI_SERVICE_NAME 3333:3333
kubectl -n $NAMESPACE port-forward svc/$WEBUI_SERVICE_NAME 8080:8080
```

Anschließend können Sie die WebUI unter http://localhost:8080 in Ihrem Browser öffnen und die API ist unter http://localhost:3333 verfügbar.

### API-Verwendung

TGI implementiert die OpenAI-kompatible API, die Sie direkt ansprechen können:

```bash
# Beispiel: Chat-Completion über die API abfragen
curl http://localhost:3333/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama/Llama-2-7b-chat-hf",
    "messages": [{"role": "user", "content": "Was ist die HAW Hamburg?"}],
    "temperature": 0.7
  }'
```

## 7. GPU-Ressourcen skalieren

Je nach Anforderung können Sie die Anzahl der verwendeten GPUs für das TGI-Deployment dynamisch anpassen:

```bash
# Skalieren auf 2 GPUs
./scripts/scale-gpu.sh --count 2

# Zurück auf 1 GPU reduzieren
./scripts/scale-gpu.sh --count 1
```

Das Skript führt folgende Aktionen aus:
1. Validiert die angeforderte GPU-Anzahl
2. Aktualisiert das Deployment mit der neuen GPU-Anzahl und aktiviert/deaktiviert den Sharded-Modus entsprechend
3. Wartet auf das erfolgreiche Rollout

Beachten Sie, dass diese Änderung einen Neustart des TGI-Pods verursacht und das Modell neu geladen werden muss.

### Wichtige Hinweise zur GPU-Skalierung

- Die maximale Anzahl von GPUs ist durch die ICC-Ressourcenbeschränkungen und die Verfügbarkeit limitiert
- Größere Modelle benötigen mehr GPU-Speicher und können von mehreren GPUs profitieren
- Alle GPUs müssen auf demselben Knoten sein, da TGI derzeit nur Sharding innerhalb eines Knotens unterstützt

## 8. GPU-Testen und Überwachen

Das Projekt bietet mehrere Skripte für Tests, Überwachung und Benchmarking der GPU-Funktionalität.

### GPU-Funktionalität testen

```bash
./scripts/test-gpu.sh
```

Dieses Skript führt folgende Tests durch:
- Prüft die NVIDIA GPU-Verfügbarkeit mit `nvidia-smi`
- Überprüft CUDA-Umgebungsvariablen
- Testet die TGI API

### GPU-Leistung überwachen

```bash
# GPU-Monitoring mit TUI (Terminal User Interface)
./scripts/monitor-gpu.sh

# Performance mit spezifischen Parametern messen
./scripts/monitor-gpu.sh -i 5 -f full -s metrics.csv
```

## 9. Fehlerbehebung

### Allgemeine Probleme

Wenn Sie Probleme mit dem Deployment haben, prüfen Sie zunächst die Logs:

```bash
# TGI-Logs anzeigen
./scripts/check-logs.sh tgi

# WebUI-Logs anzeigen
./scripts/check-logs.sh webui
```

### Häufige Probleme und Lösungen

1. **Pod bleibt hängen im Pending-Status**:
   - Überprüfen Sie, ob genügend GPU-Ressourcen verfügbar sind: `kubectl get nodes -o=custom-columns=NODE:.metadata.name,GPU:.status.capacity.'nvidia\.com/gpu'`
   - Prüfen Sie die Beschreibung des Pods: `kubectl -n $NAMESPACE describe pod $POD_NAME`

2. **TGI startet nicht wegen Out of Memory**:
   - Wechseln Sie zu einem kleineren Modell oder erhöhen Sie die Anzahl der GPUs
   - Verwenden Sie Quantisierung mit `--quantize awq`

3. **WebUI kann keine Verbindung zu TGI herstellen**:
   - Überprüfen Sie, ob der TGI-Service läuft: `kubectl -n $NAMESPACE get svc $TGI_SERVICE_NAME`
   - Testen Sie die API direkt: `kubectl -n $NAMESPACE port-forward svc/$TGI_SERVICE_NAME 3333:3333` und dann `curl http://localhost:3333/v1/models`

4. **Lange Ladezeiten für Modelle**:
   - Dies ist normal, besonders bei großen Modellen. TGI muss das Modell beim Start herunterladen und in den GPU-Speicher laden
   - Verwenden Sie das Pod-Log, um den Fortschritt zu überwachen: `kubectl -n $NAMESPACE logs -f $POD_NAME`

## 10. Weitere Performance-Optimierungen

### Shared Memory (IPC) optimieren

Für Multi-GPU-Anwendungen ist es wichtig, ausreichend Shared Memory bereitzustellen:

```yaml
volumes:
- name: dshm
  emptyDir:
    medium: Memory
    sizeLimit: 1Gi  # Shared Memory Größe
volumeMounts:
- name: dshm
  mountPath: /dev/shm
```

Diese Konfiguration ist bereits im Deployment-Skript enthalten.

### Quantisierung verwenden

Für große Modelle empfehlen wir die Verwendung von Quantisierung:

```bash
# Aktivieren Sie AWQ-Quantisierung
./scripts/change-model.sh --model "meta-llama/Llama-2-7b-chat-hf" --quantization "awq"
```

### Mixed Precision optimieren

TGI nutzt standardmäßig Mixed Precision (float16) für effiziente Inferenz:

- Verwenden Sie `--dtype=bfloat16` für besondere Modelle, die dieses Format benötigen
- Bleiben Sie bei `--dtype=float16` für die meisten Anwendungsfälle

## 11. Ressourcen bereinigen

Wenn Sie die Deployment entfernen möchten:

```bash
./scripts/cleanup.sh
```

Oder einzelne Komponenten:

```bash
kubectl -n $NAMESPACE delete deployment $TGI_DEPLOYMENT_NAME
kubectl -n $NAMESPACE delete service $TGI_SERVICE_NAME
kubectl -n $NAMESPACE delete deployment $WEBUI_DEPLOYMENT_NAME
kubectl -n $NAMESPACE delete service $WEBUI_SERVICE_NAME
```