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

| Metric | `ubuntu-24.04-arm` | `ubuntu-latest` |
| :--- | :---: | :---: |
| **🖥️ System Specs** |  |  |
| Architecture | aarch64 | x86_64 |
| OS Version | Ubuntu 24.04.5 LTS | Ubuntu 24.04.5 LTS |
| Kernel | 6.17.0-1022-azure | 6.17.0-1022-azure |
| CPU Model | Neoverse-N2 | AMD EPYC 9V45 96-Core Processor |
| vCPUs | 4 | 4 |
| RAM Total (GB) | 15.57 | 15.61 |
| Disk Total (GB) | 144.26 | 144.26 |
| Disk Free (GB) | 107.32 | 85.37 |
| **🧠 CPU Performance** |  |  |
| Sysbench Single-Thread (events/s) | **1497.61** | **1957.27** |
| Sysbench Single-Thread Avg Latency (ms) | 0.67 | 0.51 |
| Sysbench Multi-Thread (events/s) | **5968.39** | **4176.21** |
| Sysbench Multi-Thread Avg Latency (ms) | 0.67 | 0.96 |
| SHA256 Throughput (MB/s) | **2049.64** | **1987.95** |
| **💾 Memory Bandwidth** |  |  |
| Sysbench Mem Read (MiB/s) | **83498.0** | **207859.91** |
| Sysbench Mem Write (MiB/s) | **108717.79** | **63692.97** |
| **🚀 Disk IOPS & Throughput (fio)** |  |  |
| 4K Random Read IOPS | **18277.8** | **20004.9** |
| 4K Random Read Latency (ms) | 3.499 | 3.195 |
| 4K Random Read Bandwidth (MB/s) | 71.4 | 78.14 |
| 4K Random Write IOPS | **19207.2** | **19977.6** |
| 4K Random Write Latency (ms) | 3.329 | 3.198 |
| 4K Random Write Bandwidth (MB/s) | 75.03 | 78.04 |
| 1M Sequential Read (MB/s) | **374.43** | **397.73** |
| 1M Sequential Write (MB/s) | **330.38** | **259.1** |
| 4K Mixed 70/30 Total IOPS | **19572.5** | **20024.7** |


<!-- BENCHMARK_RESULTS_END -->
