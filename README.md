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
| CPU Model | Apple M1 (Virtual) | Neoverse-N2 | INTEL(R) XEON(R) PLATINUM 8573C |
| vCPUs | 3 | 4 | 4 |
| RAM Total (GB) | 7.0 | 15.57 | 15.61 |
| Disk Total (GB) | 319.51 | 144.26 | 144.26 |
| Disk Free (GB) | 96.11 | 107.31 | 85.36 |
| **🧠 CPU Performance** |  |  |  |
| Sysbench Single-Thread (events/s) | **5904533.87** | **1498.22** | **1183.43** |
| Sysbench Single-Thread Avg Latency (ms) | 0.0 | 0.67 | 0.84 |
| Sysbench Multi-Thread (events/s) | **18418341.42** | **5965.24** | **2447.82** |
| Sysbench Multi-Thread Avg Latency (ms) | 0.0 | 0.67 | 1.63 |
| SHA256 Throughput (MB/s) | **1651.86** | **2044.01** | **1658.0** |
| **💾 Memory Bandwidth** |  |  |  |
| Sysbench Mem Read (MiB/s) | **49679.53** | **90453.32** | **106386.88** |
| Sysbench Mem Write (MiB/s) | **29774.32** | **108048.71** | **48360.43** |
| **🚀 Disk IOPS & Throughput (fio)** |  |  |  |
| 4K Random Read IOPS | **30080.3** | **19954.6** | **19913.6** |
| 4K Random Read Latency (ms) | 0.493 | 3.205 | 3.211 |
| 4K Random Read Bandwidth (MB/s) | 117.5 | 77.95 | 77.79 |
| 4K Random Write IOPS | **18698.5** | **20132.9** | **19936.6** |
| 4K Random Write Latency (ms) | 0.81 | 3.176 | 3.207 |
| 4K Random Write Bandwidth (MB/s) | 73.04 | 78.64 | 77.88 |
| 1M Sequential Read (MB/s) | **5467.01** | **405.39** | **396.97** |
| 1M Sequential Write (MB/s) | **5882.82** | **342.59** | **261.49** |
| 4K Mixed 70/30 Total IOPS | **28028.4** | **20100.2** | **19980.6** |


<!-- BENCHMARK_RESULTS_END -->
