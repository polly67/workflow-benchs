# 🚀 GitHub Actions Runner Benchmarks (`workflow-benchs`)

A comprehensive benchmarking suite comparing GitHub Actions standard hosted runners for **public repositories**, specifically analyzing **x86-64 (`ubuntu-latest`) vs ARM64 (`ubuntu-24.04-arm`)**.

---

## 📌 Free GitHub-Hosted Runner Offerings for Public Repositories

According to the official [GitHub Actions Documentation](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners), GitHub provides **free and unlimited** standard hosted runners for **public repositories**.

Standard runners for public repositories are configured with **4 vCPUs and 16 GB RAM** (twice the resources of standard runners on private repositories, which receive 2 vCPUs and 8 GB RAM):

| OS / Platform | Architecture | CPU | RAM | SSD Storage | Workflow Label | Cost for Public Repos |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Linux (Ubuntu 24.04 / 22.04)** | **x86_64** | 4 vCPUs | 16 GB | 14 GB SSD | `ubuntu-latest`, `ubuntu-24.04`, `ubuntu-22.04` | **Free & Unlimited** |
| **Linux (Ubuntu ARM64)** | **ARM64 (aarch64)** | 4 vCPUs | 16 GB | 14 GB SSD | `ubuntu-24.04-arm`, `ubuntu-22.04-arm` | **Free & Unlimited** |
| **Linux (Ubuntu Slim)** | x86_64 | 1 vCPU | 5 GB | 14 GB SSD | `ubuntu-slim` | **Free & Unlimited** |
| **Windows Server** | x86_64 | 4 vCPUs | 16 GB | 14 GB SSD | `windows-latest`, `windows-2025`, `windows-2022` | **Free & Unlimited** |
| **Windows 11 ARM** | ARM64 | 4 vCPUs | 16 GB | 14 GB SSD | `windows-11-arm` | **Free & Unlimited** |
| **macOS (Apple Silicon)** | ARM64 (M-series) | 3 vCPUs | 7 GB | 14 GB SSD | `macos-latest`, `macos-14`, `macos-15` | **Free & Unlimited** |
| **macOS (Intel)** | x86_64 | 4 vCPUs | 14 GB | 14 GB SSD | `macos-15-intel` | **Free & Unlimited** |

---

## 🔬 Benchmark Methodology

The benchmark measures:
1. **CPU Performance**:
   - Single-thread execution speed (Events / sec) via `sysbench cpu` (max-prime: 20,000)
   - Multi-thread execution speed across all vCPUs via `sysbench cpu`
   - Cryptographic hashing throughput (MB/s) with SHA-256
2. **Memory Subsystem**:
   - Sequential Memory Read Bandwidth (MiB/s) via `sysbench memory`
   - Sequential Memory Write Bandwidth (MiB/s) via `sysbench memory`
3. **Storage & Disk I/O Performance (`fio`)**:
   - **4K Random Read IOPS** & Average Latency (`libaio`, `iodepth=64`, `direct=1`)
   - **4K Random Write IOPS** & Average Latency (`libaio`, `iodepth=64`, `direct=1`)
   - **1M Sequential Read Throughput** (MB/s)
   - **1M Sequential Write Throughput** (MB/s)
   - **4K Mixed 70/30 Read/Write IOPS**

---

<!-- BENCHMARK_RESULTS_START -->

# 📊 GitHub Actions Free Runners Benchmark Comparison

Comparison of GitHub Actions standard hosted runners for public repositories (x86-64 vs ARM64).

| Metric | `macos-latest` | `ubuntu-24.04-arm` | `ubuntu-latest` |
| :--- | :---: | :---: | :---: |
| **🖥️ System Specs** |  |  |  |
| Architecture | arm64 | aarch64 | x86_64 |
| OS Version | macOS 26.6.2 | Ubuntu 24.04.5 LTS | Ubuntu 24.04.5 LTS |
| Kernel | 25.6.0 | 6.17.0-1022-azure | 6.17.0-1022-azure |
| CPU Model | Apple M1 (Virtual) | Neoverse-N2 | AMD EPYC 7763 64-Core Processor |
| vCPUs | 3 | 4 | 4 |
| RAM Total (GB) | 7.0 | 15.57 | 15.61 |
| Disk Total (GB) | 319.51 | 144.26 | 144.26 |
| Disk Free (GB) | 96.19 | 107.32 | 85.37 |
| **🧠 CPU Performance** |  |  |  |
| Sysbench Single-Thread (events/s) | **7091172.95** | **1497.28** | **1442.78** |
| Sysbench Single-Thread Avg Latency (ms) | 0.0 | 0.67 | 0.69 |
| Sysbench Multi-Thread (events/s) | **22261411.49** | **5964.72** | **3154.2** |
| Sysbench Multi-Thread Avg Latency (ms) | 0.0 | 0.67 | 1.27 |
| SHA256 Throughput (MB/s) | **2068.07** | **2039.26** | **1508.63** |
| **💾 Memory Bandwidth** |  |  |  |
| Sysbench Mem Read (MiB/s) | **26468.99** | **87349.9** | **100682.98** |
| Sysbench Mem Write (MiB/s) | **42583.37** | **107737.74** | **44572.27** |
| **🚀 Disk IOPS & Throughput (fio)** |  |  |  |
| 4K Random Read IOPS | **40882.7** | **20066.5** | **19527.3** |
| 4K Random Read Latency (ms) | 0.361 | 3.183 | 3.271 |
| 4K Random Read Bandwidth (MB/s) | 159.7 | 78.38 | 76.28 |
| 4K Random Write IOPS | **25823.8** | **20087.4** | **19614.9** |
| 4K Random Write Latency (ms) | 0.572 | 3.178 | 3.257 |
| 4K Random Write Bandwidth (MB/s) | 100.87 | 78.47 | 76.62 |
| 1M Sequential Read (MB/s) | **8170.57** | **404.76** | **406.69** |
| 1M Sequential Write (MB/s) | **6484.5** | **343.12** | **405.48** |
| 4K Mixed 70/30 Total IOPS | **37376.5** | **20106.8** | **19596.5** |


<!-- BENCHMARK_RESULTS_END -->
