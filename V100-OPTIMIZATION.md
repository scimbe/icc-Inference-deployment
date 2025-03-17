# V100 GPU-Optimierung für TGI und vLLM

Diese technische Dokumentation beschreibt die spezifischen Optimierungen und Best Practices für den Einsatz von TGI (Text Generation Inference) und vLLM auf NVIDIA Tesla V100 GPUs in der ICC-Umgebung.

## Inhaltsverzeichnis

- [Hardwarespezifikation: Tesla V100](#hardwarespezifikation-tesla-v100)
- [Häufige Herausforderungen](#häufige-herausforderungen)
- [TGI-Optimierungsstrategien](#tgi-optimierungsstrategien)
- [vLLM-Optimierungsstrategien](#vllm-optimierungsstrategien)
- [Multi-GPU-Konfigurationen](#multi-gpu-konfigurationen)
- [Quantisierungstechniken](#quantisierungstechniken)
- [Überwachung und Fehlerdiagnose](#überwachung-und-fehlerdiagnose)
- [Modellspezifische Empfehlungen](#modellspezifische-empfehlungen)

## Hardwarespezifikation: Tesla V100

Die NVIDIA Tesla V100 GPU, die in der ICC verfügbar ist, hat folgende Spezifikationen:

| Eigenschaft | Wert |
|-------------|------|
| GPU-Speicher | 16 GB HBM2 |
| CUDA-Kerne | 5,120 |
| Tensor-Kerne | 640 |
| Speicherbandbreite | 900 GB/s |
| Compute-Capability | 7.0 |
| Architektur | Volta |

Diese Hardware hat einige spezifische Eigenschaften, die bei LLM-Inferenz berücksichtigt werden müssen:

- **Limitierter Speicher**: Mit 16GB RAM pro GPU gibt es Einschränkungen für große Modelle
- **Ältere Architektur**: Im Vergleich zu A100/H100 fehlen einige Optimierungen
- **HBM2-Speicher**: Hohe Bandbreite, aber empfindlich bei Speicherfragmentierung

## Häufige Herausforderungen

Bei der Ausführung von LLMs auf V100 GPUs treten häufig folgende Probleme auf:

### 1. Out-of-Memory (OOM) Fehler

```
CUDA error: out of memory
Shard process was signaled to shutdown with signal 9
```

Diese Fehler treten auf, wenn das Modell den verfügbaren GPU-Speicher überschreitet. Besonders häufig bei:
- Modellen >7B ohne Quantisierung auf einer GPU
- Langen Eingabekontexten
- Ungünstigen Konfigurationsparametern

### 2. NCCL-Kommunikationsprobleme bei Multi-GPU

```
NCCL error: unhandled system error (Connection timed out)
```

Diese können auftreten, wenn die GPU-Kommunikation bei Multi-GPU-Setups nicht richtig konfiguriert ist.

### 3. Flash Attention Inkompatibilität

```
CUDA error: no kernel image is available for execution on the device
```

V100 GPUs unterstützen einige neuere Flash Attention-Implementierungen nicht vollständig.

## TGI-Optimierungsstrategien

Text Generation Inference (TGI) kann für V100 GPUs spezifisch optimiert werden:

### Parameter-Optimierung

| Parameter | Optimaler Wert | Grund |
|-----------|---------------|-------|
| `--cuda-memory-fraction` | 0.85 | Verhindert OOM, lässt Puffer für Systemoperationen |
| `--max-input-length` | 2048 | Reduzierte Kontextgröße für V100 |
| `--max-total-tokens` | 4096 | Limitierte kombinierte Token-Anzahl |
| `--max-batch-prefill-tokens` | 4096 | Verhindert Speicherüberlastung beim Batch-Prefill |
| `--disable-custom-kernels` | true | Sorgt für bessere Kompatibilität mit V100 |
| `--max-parallel-loading-workers` | GPU_COUNT | Optimiert paralleles Laden im Multi-GPU-Setup |
| `--max-concurrent-requests` | 8 × GPU_COUNT | Skaliert mit der GPU-Anzahl für optimalen Durchsatz |
| `--sharded` | true | Aktiviert bei Multi-GPU für parallele Verarbeitung |
| `--num-shard` | GPU_COUNT | Sorgt für optimale Parallelisierung |

### CUDA-Umgebungsvariablen

```bash
# Kritische Einstellungen
CUDA_VISIBLE_DEVICES="0,1"    # GPUs explizit definieren
NCCL_DEBUG="INFO"             # Debug-Informationen für Multi-GPU
NCCL_DEBUG_SUBSYS="ALL"       # Detaillierte Subsystem-Infos
NCCL_P2P_DISABLE="0"          # Peer-to-Peer-Kommunikation erlauben
NCCL_IB_DISABLE="0"           # InfiniBand-Kommunikation erlauben
NCCL_P2P_LEVEL="NVL"          # Optimale Peer-to-Peer-Kommunikation
NCCL_SOCKET_IFNAME="^lo,docker" # Socket-Interface für NCCL
NCCL_SHM_DISABLE="0"          # Shared Memory nutzen
```

### Shared Memory Optimierung

Die Default-Shared-Memory-Größe von Docker ist oft zu gering für Multi-GPU-Inferenz:

| GPU-Anzahl | Empfohlene DSHM-Größe |
|------------|----------------------|
| 1 GPU | 4Gi - 8Gi |
| 2 GPUs | 8Gi - 16Gi |
| 4 GPUs | 16Gi - 32Gi |

Diese wird in der K8s-Konfiguration über das dshm-Volume festgelegt.

## vLLM-Optimierungsstrategien

vLLM bietet teilweise bessere Performance als TGI, erfordert aber spezifische Konfigurationen für V100:

### Key-Parameter

| Parameter | Optimaler Wert | Erläuterung |
|-----------|---------------|------------|
| `--block-size` | 16 | Optimale Blockgröße für die Speicherverwaltung |
| `--swap-space` | 4 | Erlaubt Paging zwischen CPU und GPU |
| `--max-model-len` | ≤4096 | Kontext-Limit auf V100 |
| `--tensor-parallel-size` | GPU_COUNT | Für Multi-GPU-Sharding |

### PagedAttention

vLLM verwendet PagedAttention, eine speichereffiziente Technik. Auf V100 sollten Sie:

- Kleinere Blockgrößen verwenden (8 oder 16)
- Swap-Space aktivieren für längere Sequenzen
- Bei Multi-GPU immer Tensor-Parallelismus aktivieren

## Multi-GPU-Konfigurationen

Für größere Modelle empfehlen wir die Nutzung mehrerer GPUs:

### TGI Multi-GPU (Sharded Mode)

Im TGI-Sharded-Modus wird das Modell auf mehrere GPUs aufgeteilt, wobei jede GPU einen Teil der Modellgewichte hält:

- **Konfiguration**: `--sharded=true --num-shard=<GPU_COUNT>`
- **Worker-Optimierung**: `--max-parallel-loading-workers=<GPU_COUNT>`
- **Durchsatz-Optimierung**: `--max-concurrent-requests=<8 × GPU_COUNT>`
- **Shared Memory**: DSHM-Größe proportional zur GPU-Anzahl skalieren (`<8 × GPU_COUNT>Gi`)

TGI nutzt den Sharded-Modus, um das Modell horizontal zu teilen, was besonders für große Modelle (13B+) auf V100s effektiv ist.

### vLLM Multi-GPU (Tensor Parallel)

vLLM verwendet Tensor-Parallelismus, um die Berechnungen auf mehrere GPUs zu verteilen:

- **Konfiguration**: `--tensor-parallel-size=<GPU_COUNT>`
- **Speicheroptimierung**: `--block-size=16 --swap-space=4`
- **NCCL-Optimierung**: Wichtig für effiziente Kommunikation zwischen GPUs

Der Tensor-Parallelismus in vLLM eignet sich besonders für Szenarien mit hohem Durchsatz und kann die GPU-Auslastung im Vergleich zum Sharded-Modus von TGI verbessern.

### V100-spezifische Multi-GPU-Optimierungen

- **NCCL-Umgebungsvariablen** sind entscheidend für stabile Multi-GPU-Performance
- **Alle GPUs müssen auf demselben Knoten** sein, Node-übergreifendes Sharding wird nicht unterstützt
- **Shared Memory (dshm)** muss ausreichend groß sein für Inter-GPU-Kommunikation
- **dshm-Größe skaliert automatisch** mit der GPU-Anzahl in unseren Deployment-Skripten

## Quantisierungstechniken

Quantisierung reduziert den Speicherverbrauch erheblich und ist oft erforderlich für größere Modelle auf V100:

### AWQ-Quantisierung

```
--quantize=awq
```

Diese reduziert den Speicherbedarf um ca. 75% mit minimalem Qualitätsverlust. Empfohlen für:
- 7B-Modelle auf einer V100 (Mistral, Llama usw.)
- 13B-Modelle auf zwei V100s

### GPTQ-Quantisierung

```
--quantize=gptq
```

Alternative Quantisierungsmethode mit guter Leistung, besonders bei vorquantisierten Modellen wie TheBloke's GPTQ-Varianten. Vorteile:
- Größere Community-Unterstützung
- Mehr vorquantisierte Modelle verfügbar
- Gute Balance zwischen Qualität und Geschwindigkeit

### Vergleich: Speicheranforderungen

| Modellgröße | Standard (BF16) | AWQ/GPTQ | GPUs für Standard | GPUs für AWQ/GPTQ |
|-------------|----------------|-----|------------------|-------------|
| 7B | ~14 GB | ~4 GB | 1 | 1 |
| 13B | ~26 GB | ~7 GB | 2 | 1 |
| 34B | ~68 GB | ~17 GB | 4+ | 2 |
| 70B | ~140 GB | ~35 GB | 9+ | 3 |

## Überwachung und Fehlerdiagnose

### Wichtige Monitoring-Befehle

```bash
# GPU-Auslastung überwachen
./scripts/monitor-gpu.sh

# Logs auf Fehler analysieren
./scripts/check-logs.sh tgi -a   # für TGI
./scripts/check-logs.sh vllm -a  # für vLLM

# GPU-Funktionalität testen
./scripts/test-gpu.sh

# V100-Kompatibilität prüfen
./scripts/test-v100-compatibility.sh
```

### Typische Fehlermuster und Lösungen

| Fehlermeldung | Wahrscheinliche Ursache | Lösungsansatz |
|---------------|------------------------|---------------|
| `CUDA out of memory` | Speicherübernutzung | Quantisierung, kleineres Modell, mehr GPUs |
| `Shard process shutdown` | OOM-Killer | Reduzierte Batchgröße, kleinere Kontextlänge |
| `NCCL error` | Multi-GPU-Kommunikation | NCCL-Variablen prüfen, shared memory erhöhen |
| `no kernel image` | Inkompatible CUDA-Kernel | Custom Kernels deaktivieren |
| `unrecognized arguments` | Parameterinkompatibilität | Parameter überprüfen, aktualisieren oder entfernen |

## Modellspezifische Empfehlungen

### Optimale Konfigurationen für V100

| Modell | Empfohlene Konfiguration | max_tokens | Quantisierung | Multi-GPU |
|--------|--------------------------|------------|---------------|-----------|
| microsoft/phi-2 | 1 GPU | 4096 | Keine notwendig | Nein |
| google/gemma-2b | 1 GPU | 4096 | Keine notwendig | Nein |
| TheBloke/Mistral-7B-Instruct-v0.2-GPTQ | 1 GPU | 4096 | GPTQ | Nein |
| mistralai/Mistral-7B | 1 GPU | 4096 | AWQ | Nein |
| meta-llama/Llama-2-7b | 1 GPU | 4096 | AWQ | Nein |
| TheBloke/Llama-2-13b-chat-GPTQ | 1-2 GPUs | 4096 | GPTQ | Optional |



### Engine-Vergleich: TGI vs vLLM für V100

| Modelltyp | Beste Engine | Grund |
|-----------|-------------|-------|
| <7B Modelle | TGI oder vLLM | Beide funktionieren gut, TGI einfacher zu konfigurieren |
| 7-13B Modelle | vLLM für Durchsatz, TGI für Stabilität | vLLM: besserer Durchsatz, TGI: stabilere Multiuser-Unterstützung |
| MoE-Modelle (Mixtral) | TGI | Bessere Unterstützung für Mixture-of-Experts |
| Quantisierte GPTQ-Modelle | vLLM | Bessere GPTQ-Integration |
| Quantisierte AWQ-Modelle | TGI | Bessere AWQ-Integration |
| Multi-GPU-Performance | vLLM leichter Vorteil | Tensor-Parallelismus kann effizienter sein als Sharding |

### Performance-Vergleich 

| Modell | Engine | Konfiguration | Tokens/Sekunde | Latenz erste Token |
|--------|--------|---------------|----------------|-------------------|
| TODO | VLLM | 1 GPU, AWQ | ... | ... |

## Erweiterte Optimierungen

### Kernel-Optimierungen

Für TGI können Sie Flash Attention und andere Optimierungen deaktivieren:

```
--disable-flash-attention=true
--disable-custom-kernels
```

### vLLM-spezifische Einstellungen

```
--gpu-memory-utilization=0.85  # Verhindert OOM
--enforce-eager               # Vermeidet spekulative CUDA-Operationen
```

### Containerization-Tipps

```
# Wichtige Docker/Kubernetes-Flags
--ipc=host              # Shared memory erhöhen
--ulimit memlock=-1     # Speicher-Locks erlauben
```

### Temperatur-Management

V100 GPUs können bei anhaltender Belastung heiß werden. Achten Sie auf Temperaturen über 80°C und überlegen Sie, `CUDA_MEMORY_FRACTION` zu reduzieren, wenn die GPUs überhitzen.

### Optimierungen für spezifische NCCL-Probleme

Falls Sie NCCL-Kommunikationsprobleme beobachten:

1. **P2P-Kommunikation deaktivieren**, wenn mehrere GPUs auf separaten PCIe-Switches liegen:
   ```bash
   export NCCL_P2P_DISABLE=1
   ```

2. **IB-Kommunikation deaktivieren**, wenn InfiniBand nicht optimal konfiguriert ist:
   ```bash
   export NCCL_IB_DISABLE=1
   ```

3. **Socket-Interface explizit angeben**, wenn Docker-Netzwerk Probleme bereitet:
   ```bash
   export NCCL_SOCKET_IFNAME="eth0"  # oder entsprechendes Interface
   ```

4. **Debugging aktivieren** für detaillierte Diagnose:
   ```bash
   export NCCL_DEBUG=INFO
   export NCCL_DEBUG_SUBSYS=ALL
   ```

## Schlussfolgerung

Die V100 GPU ist nach wie vor ein leistungsfähiger Kandidat für LLM-Inferenz, benötigt jedoch sorgfältige Optimierung und Konfiguration, besonders für größere Modelle. Mit den richtigen Einstellungen und Quantisierungstechniken können Sie bis zu 13B-Modelle effizient ausführen, während größere Modelle wahrscheinlich neuere GPU-Generationen erfordern.

Die in diesem Dokument beschriebenen Optimierungen sind in den Skripten dieses Repositories bereits implementiert und können durch einfache Konfigurationsänderungen angepasst werden. Die Deployments sind sowohl für TGI als auch für vLLM optimiert, mit besonderem Fokus auf Multi-GPU-Konfigurationen und parallele Ausführung.
