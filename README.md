# ICC vLLM Deployment

Automatisierte Bereitstellung von vLLM mit GPU-Unterstützung auf der HAW Hamburg Informatik Compute Cloud (ICC). Das Projekt nutzt OpenAI-kompatible vLLM-Server und Open WebUI als Benutzeroberfläche.

## Übersicht

Dieses Repository enthält Scripts und Konfigurationsdateien, um vLLM mit Multi-GPU-Unterstützung (bis zu 4 GPUs) auf der ICC der HAW Hamburg zu deployen. Dies ermöglicht die Bereitstellung von LLM-Inferenzdiensten mit hoher Performance und die Verwendung von größeren Modellen, die eine einzelne GPU überfordern würden.

## Funktionen

- **Multi-GPU-Unterstützung**: Bis zu 4 Tesla V100 GPUs können für ein Modell verwendet werden (Tensor Parallelism)
- **Beliebige Modelle**: Unterstützt das Laden verschiedener HuggingFace-Modelle wie Llama, Mistral, Gemma, usw.
- **OpenAI API-kompatibel**: vLLM implementiert die OpenAI API, was die Integration mit verschiedenen Tools vereinfacht
- **Open WebUI Frontend**: Benutzerfreundliche Weboberfläche für die Interaktion mit dem LLM
- **Dynamisches Modell-Loading**: Einfaches Wechseln zwischen verschiedenen Modellen
- **Quantisierung**: Unterstützung für AWQ und andere Quantisierungsmethoden, um den Speicherbedarf zu reduzieren

## Voraussetzungen

- HAW Hamburg infw-Account mit Zugang zur ICC
- kubectl installiert
- Eine aktive VPN-Verbindung zum HAW-Netz (wenn außerhalb des HAW-Netzes)
- (Optional) Make installiert für vereinfachte Befehle

## Schnellstart

```bash
# Repository klonen
git clone https://github.com/scimbe/icc-vllm-deployment.git
cd icc-vllm-deployment

# ICC-Zugang einrichten
./scripts/icc-login.sh

# Konfiguration anpassen
cp configs/config.example.sh configs/config.sh
vim configs/config.sh  # Passen Sie Ihre Namespace-Informationen an

# Ausführungsberechtigungen für Skripte setzen
./scripts/set-permissions.sh

# Deployment ausführen
./deploy.sh
```

## Detaillierte Anleitung

Eine ausführliche Schritt-für-Schritt-Anleitung finden Sie in der [DOCUMENTATION.md](DOCUMENTATION.md) Datei.

## GPU-Ressourcen skalieren

Um die Performance zu optimieren oder größere Modelle zu unterstützen, können Sie die Anzahl der GPUs dynamisch anpassen:

```bash
# Skalieren auf mehr GPUs für verbesserte Performance oder größere Modelle
./scripts/scale-gpu.sh --count 2

# Reduzieren auf 1 GPU, wenn nicht alle Ressourcen benötigt werden
./scripts/scale-gpu.sh --count 1
```

## Modellauswahl

vLLM unterstützt verschiedene Modelle von HuggingFace. Sie können das Modell in der Konfigurationsdatei oder bei der Ausführung angeben:

```bash
# Modell in der Konfiguration ändern
./scripts/change-model.sh --model "meta-llama/Llama-2-7b-chat-hf"

# Andere Beispiele:
# ./scripts/change-model.sh --model "google/gemma-7b-it"
# ./scripts/change-model.sh --model "mistralai/Mistral-7B-Instruct-v0.2"
# ./scripts/change-model.sh --model "microsoft/phi-2"
```

## GPU-Überwachung

Überwachen Sie die GPU-Auslastung in Echtzeit:

```bash
./scripts/monitor-gpu.sh
```

## Architektur

Die Deployment-Architektur besteht aus zwei Hauptkomponenten:

1. **vLLM-Server**:
   - Läuft als Kubernetes-Pod mit Multi-GPU-Unterstützung
   - Bietet eine OpenAI-kompatible API über Port 8000
   - Lädt und verwaltet das LLM-Modell

2. **Open WebUI**:
   - Benutzerfreundliche Weboberfläche für die Interaktion mit dem LLM
   - Verbindet sich mit dem vLLM-Server über die OpenAI-kompatible API
   - Läuft als separater Kubernetes-Pod

## Troubleshooting

Bei Problemen mit der GPU-Funktionalität oder Modellanpassung können folgende Schritte helfen:

1. Überprüfen Sie die GPU-Kompatibilität: `./scripts/check-gpu-compatibility.sh`
2. Testen Sie die GPU-Funktionalität: `./scripts/test-gpu.sh`
3. Überprüfen Sie die Deployment-Konfiguration: `kubectl -n $NAMESPACE get deployment $VLLM_DEPLOYMENT_NAME -o yaml`
4. Prüfen Sie die Logs des vLLM-Pods: `./scripts/check-logs.sh`

## Lizenz

Dieses Projekt steht unter der [MIT-Lizenz](LICENSE).