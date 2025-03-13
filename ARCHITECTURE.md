# ICC-vLLM-Deployment Architekturübersicht

Diese Dokumentation beschreibt die Architektur des ICC-vLLM-Deployment-Projekts, das die Bereitstellung von vLLM mit Multi-GPU-Unterstützung auf der Informatik Compute Cloud (ICC) der HAW Hamburg ermöglicht.

## Architekturdiagramm

```mermaid
flowchart TD
    %% Akteure
    student[Student: Nutzt LLM für Textgenerierung]
    researcher[Forscher: Experimentiert mit verschiedenen Modellen]
    admin[Administrator: Verwaltet Deployments und GPU-Ressourcen]

    %% Haupteingangspunkte
    subgraph entry[Eingangspunkte]
        k8s_cli[kubectl CLI: Primäre Steuerung]
        make_cmd[Make: Vereinfachte Befehle]
        bash_scripts[Bash-Scripts: Automatisierte Workflows]
    end

    %% HAW-Infrastruktur
    subgraph haw_infra[HAW-Infrastruktur]
        vpn[HAW-VPN: Netzwerkzugang]
        icc_login[ICC-Login-Portal: Authentifizierung & Kubeconfig]
    end

    %% ICC Kubernetes Cluster
    subgraph k8s_cluster[ICC Kubernetes Cluster]
        subgraph namespace[Benutzer-Namespace w*-default]
            subgraph vllm_deploy[vLLM-Deployment]
                vllm_pod[vLLM-Pod: Führt Inferenz aus]
                vllm_svc[vLLM-Service: OpenAI-API]
                model_cache[HuggingFace Cache: Modellspeicher]
            end

            subgraph webui_deploy[WebUI-Deployment]
                webui_pod[WebUI-Pod: Benutzeroberfläche]
                webui_svc[WebUI-Service: Interner Zugriff]
            end

            subgraph gpu_resources[GPU-Ressourcen]
                gpu_toleration[GPU-Toleration: Ermöglicht Scheduling]
                subgraph multi_gpu[Multi-GPU-Konfiguration]
                    gpu1[Tesla V100 GPU 1]
                    gpu2[Tesla V100 GPU 2]
                    gpu3[Tesla V100 GPU 3]
                    gpu4[Tesla V100 GPU 4]
                end
            end

            ingress[Optional: Ingress für externen Zugriff]
        end

        subgraph k8s_resources[K8s-Ressourcenmanagement]
            subns[Subnamespace-Verwaltung]
            rbac[RBAC: Zugriffssteuerung]
            scheduler[K8s-Scheduler: Pod-Platzierung]
        end
    end

    %% Lokale Entwicklungsumgebung
    subgraph local_dev[Lokale Entwicklungsumgebung]
        git_repo[Git Repository: icc-vllm-deployment]
        config[Konfigurationsdateien: config.sh]
        port_forward[Port-Forwarding: Lokaler Zugriff]
    end

    %% Anwendungskomponenten
    subgraph components[Anwendungskomponenten]
        vllm_engine[vLLM Engine: LLM-Inferenz]
        openai_api[OpenAI-kompatible API: REST-Schnittstelle]
        open_webui[Open WebUI: Benutzerfreundliche Oberfläche]
        llm_models[LLM-Modelle: Llama, Mistral, Gemma, etc.]
        tensor_parallel[Tensor Parallelism: Multi-GPU-Nutzung]
    end

    %% Beziehungen - Nutzer zu System
    student -->|Interagiert mit| open_webui
    researcher -->|Experimentiert mit| openai_api
    admin -->|Verwaltet| k8s_cli

    %% Einrichtung und Zugang
    admin -->|Nutzt| bash_scripts
    admin -->|Vereinfachte Befehle| make_cmd
    bash_scripts -->|Automatisiert| k8s_cli
    admin -->|Verbindet über| vpn
    vpn -->|Ermöglicht Zugriff auf| icc_login
    icc_login -->|Generiert| config
    config -->|Konfiguriert| k8s_cli

    %% Deploymentprozesse
    k8s_cli -->|Erstellt| vllm_deploy
    k8s_cli -->|Erstellt| webui_deploy
    vllm_deploy -->|Nutzt| gpu_resources
    gpu_toleration -->|Erlaubt Scheduling auf| multi_gpu
    vllm_pod -->|Hosted auf| multi_gpu
    k8s_cli -->|Optional erstellt| ingress

    %% Komponenten-Beziehungen
    vllm_pod -->|Hostet| vllm_engine
    vllm_engine -->|Nutzt| tensor_parallel
    tensor_parallel -->|Verteilt Last auf| multi_gpu
    vllm_engine -->|Bietet| openai_api
    vllm_engine -->|Lädt| llm_models
    vllm_svc -->|Exponiert| openai_api
    webui_pod -->|Hostet| open_webui
    open_webui -->|Verbindet mit| vllm_svc
    vllm_pod -->|Speichert in| model_cache

    %% Zugriff auf Services
    k8s_cli -->|Ermöglicht| port_forward
    port_forward -->|Zugriff auf| vllm_svc
    port_forward -->|Zugriff auf| webui_svc
    ingress -->|Öffentlicher Zugriff auf| webui_svc

    %% Kubernetes Ressourcenverwaltung
    k8s_cluster -->|Verwaltet| namespace
    namespace -->|Teil von| subns
    rbac -->|Kontrolliert Zugriff auf| namespace
    scheduler -->|Platziert| vllm_pod
    scheduler -->|Platziert| webui_pod

    %% Lokale vs. ICC Entwicklung
    local_dev -->|Entwicklung und Tests| git_repo
    git_repo -->|Deployment auf| k8s_cluster
```

## Hauptkomponenten

### 1. vLLM-Inferenzserver

vLLM (very Large Language Model) ist ein hochperformanter LLM-Inferenzserver mit folgenden Eigenschaften:

- **Hoher Durchsatz**: Verarbeitet mehrere Anfragen parallel dank PagedAttention-Technologie
- **Multi-GPU-Unterstützung**: Verteilt große Modelle über mehrere GPUs mittels Tensor-Parallelismus
- **OpenAI-kompatible API**: Implementiert die gleiche API wie OpenAI, was die Integration erleichtert
- **Modellkompatibilität**: Unterstützt eine Vielzahl von HuggingFace-Modellen
- **Quantisierung**: Unterstützt verschiedene Quantisierungsmethoden (AWQ, GPTQ) zur Reduzierung des Speicherbedarfs

vLLM wird als Kubernetes-Deployment bereitgestellt, das auf Nodes mit NVIDIA-GPUs orchestriert wird.

### 2. Open WebUI

Open WebUI ist eine benutzerfreundliche Frontend-Anwendung, die ursprünglich für Ollama entwickelt wurde, aber auch mit OpenAI-kompatiblen APIs arbeiten kann. Eigenschaften:

- **Chat-Interface**: Intuitive Benutzeroberfläche für die Interaktion mit LLMs
- **Konversationsspeicher**: Speichert Chatverläufe für zukünftige Referenz
- **Modellauswahl**: Unterstützt die Auswahl verschiedener Modelle (im Fall von vLLM ist dies meist nur ein Modell pro Deployment)
- **Parametersteuerung**: Erlaubt die Anpassung von Inferenzparametern wie Temperatur, Top-P usw.

Die WebUI wird als separates Kubernetes-Deployment bereitgestellt, das mit dem vLLM-Service kommuniziert.

### 3. Multi-GPU-Konfiguration

Die ICC stellt NVIDIA Tesla V100 GPUs bereit, die für die LLM-Inferenz optimiert sind:

- **Tensor-Parallelismus**: Verteilt die Tensor-Operationen eines Modells auf mehrere GPUs
- **GPU-Scheduling**: Die Kubernetes-Konfiguration sorgt dafür, dass die Pods auf Nodes mit der erforderlichen GPU-Anzahl platziert werden
- **Ressourcenlimits**: Die Deployments definieren präzise Ressourcenanforderungen für die GPUs

### 4. Kubernetes-Ressourcen

Das Deployment nutzt mehrere Kubernetes-Ressourcen:

- **Deployments**: Definieren die Container-Konfigurationen für vLLM und Open WebUI
- **Services**: Stellen interne Endpunkte für die Kommunikation zwischen den Komponenten bereit
- **PersistentVolumeClaims**: Optional für die persistente Speicherung von Modellen
- **ConfigMaps/Secrets**: Verwalten Konfigurationen und sensible Daten

## Kommunikations- und Datenfluss

1. **Modellladeprozess**:
   - vLLM lädt beim Start das konfigurierte Modell von HuggingFace oder aus dem lokalen Cache
   - Das Modell wird im GPU-Speicher gemäß der Tensor-Parallelismus-Konfiguration verteilt
   - Bei Multi-GPU-Setups werden die Modellgewichte auf mehrere GPUs verteilt

2. **Inferenzprozess**:
   - Die WebUI nimmt Benutzereingaben über das Chat-Interface entgegen
   - Die Anfrage wird über die OpenAI-kompatible API an den vLLM-Server gesendet
   - vLLM verarbeitet die Anfrage und nutzt dabei die konfigurierten GPUs
   - Die Antwort wird zurück an die WebUI gesendet und dem Benutzer präsentiert

3. **Administration**:
   - Administratoren verwenden die bereitgestellten Skripte, um das Deployment zu verwalten
   - Die Konfiguration kann über die `config.sh` angepasst werden
   - GPU-Ressourcen können dynamisch skaliert werden

## Sicherheit und Zugriffskontrolle

- **RBAC**: Kubernetes Role-Based Access Control regelt die Zugriffsrechte innerhalb des Clusters
- **NetworkPolicies**: Optional können Netzwerkrichtlinien den Traffic zwischen den Pods einschränken
- **Ingress**: Für externe Zugänglichkeit kann ein Ingress mit TLS-Termination konfiguriert werden

## Vorteile dieser Architektur

1. **Skalierbarkeit**: Durch die Nutzung von Kubernetes kann das System bei Bedarf horizontal und vertikal skaliert werden
2. **Flexibilität**: Die Modellauswahl kann dynamisch angepasst werden
3. **Performance**: Multi-GPU-Unterstützung und PagedAttention ermöglichen hohen Durchsatz und niedrige Latenz
4. **Isolierung**: Jeder Benutzer erhält eine isolierte Umgebung im eigenen Namespace
5. **Einfache Verwaltung**: Automatisierte Skripte vereinfachen die Verwaltung des Systems

## Einschränkungen und Herausforderungen

1. **GPU-Verfügbarkeit**: Die Anzahl verfügbarer GPUs in der ICC ist begrenzt
2. **Node-gebundener Tensor-Parallelismus**: vLLM unterstützt Tensor-Parallelismus derzeit nur innerhalb eines Knotens
3. **Speicherbeschränkungen**: Die V100 GPUs haben jeweils 16GB Speicher, was den Einsatz sehr großer Modelle ohne Quantisierung erschwert
4. **Zeit für Modellwechsel**: Das Laden neuer Modelle erfordert einen Neustart des vLLM-Pods und kann einige Zeit in Anspruch nehmen

## Deployment-Workflow

1. **Vorbereitung**: Einrichtung des ICC-Zugangs und Konfiguration des Namespaces
2. **Konfiguration**: Anpassung der Parameter in der `config.sh`
3. **Deployment**: Ausführung der Skripte zum Erstellen der Kubernetes-Ressourcen
4. **Validierung**: Überprüfung der Pod-Logs und Sicherstellen, dass das Modell geladen wurde
5. **Zugriff**: Port-Forwarding oder Ingress-Konfiguration für den Zugriff auf die WebUI
6. **Nutzung**: Interaktion mit dem LLM über die WebUI oder direkt über die API
7. **Wartung**: Überwachung der GPU-Auslastung und gegebenenfalls Skalierung der Ressourcen

Diese Architektur bietet eine flexible, skalierbare und benutzerfreundliche Lösung für den Einsatz von Large Language Models in der akademischen Umgebung der HAW Hamburg.