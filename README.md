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

| Metric | `ubuntu-latest` | `ubuntu-24.04-arm` | `macos-latest` | `macos-15-intel` |
| :--- | :---: | :---: | :---: | :---: |
| **🖥️ System Specs** |  |  |  |  |
| Architecture | x86_64 | aarch64 | arm64 | x86_64 |
| OS Version | Ubuntu 24.04.5 LTS | Ubuntu 24.04.5 LTS | macOS 26.6.2 | macOS 15.7.9 |
| Kernel | 6.17.0-1022-azure | 6.17.0-1022-azure | 25.6.0 | 24.6.0 |
| CPU Model | AMD EPYC 7763 64-Core Processor | Neoverse-N2 | Apple M1 (Virtual) | Intel(R) Core(TM) i7-8700B CPU @ 3.20GHz |
| vCPUs | 4 | 4 | 3 | 4 |
| RAM Total (GB) | 15.61 | 15.57 | 7.0 | 14.0 |
| Disk Total (GB) | 144.26 | 144.26 | 319.51 | 324.68 |
| Disk Free (GB) | 85.36 | 107.32 | 96.3 | 108.4 |
| **🧠 CPU Performance** |  |  |  |  |
| Sysbench Single-Thread (events/s) | **1441.36** | **1498.51** | **9275006.43** | **3533870.11** |
| Sysbench Single-Thread Avg Latency (ms) | 0.69 | 0.67 | 0.0 | 0.0 |
| Sysbench Multi-Thread (events/s) | **3151.31** | **5965.77** | **25401759.7** | **10654345.91** |
| Sysbench Multi-Thread Avg Latency (ms) | 1.27 | 0.67 | 0.0 | 0.0 |
| SHA256 Throughput (MB/s) | **1506.29** | **2038.33** | **2084.64** | **394.45** |
| **💾 Memory Bandwidth** |  |  |  |  |
| Sysbench Mem Read (MiB/s) | **99873.81** | **120584.81** | **44773.57** | **63150.23** |
| Sysbench Mem Write (MiB/s) | **46874.83** | **100477.49** | **45144.71** | **37940.54** |
| **🚀 Disk IOPS & Throughput (fio)** |  |  |  |  |
| 4K Random Read IOPS | **19551.7** | **20107.6** | **53086.4** | **7739.4** |
| 4K Random Read Latency (ms) | 3.266 | 3.177 | 0.269 | 1.909 |
| 4K Random Read Bandwidth (MB/s) | 76.37 | 78.55 | 207.37 | 30.23 |
| 4K Random Write IOPS | **19573.2** | **19974.5** | **31468.9** | **6986.1** |
| 4K Random Write Latency (ms) | 3.264 | 3.196 | 0.472 | 2.051 |
| 4K Random Write Bandwidth (MB/s) | 76.46 | 78.03 | 122.93 | 27.29 |
| 1M Sequential Read (MB/s) | **405.76** | **405.09** | **10079.68** | **3427.77** |
| 1M Sequential Write (MB/s) | **404.95** | **342.43** | **9236.65** | **2257.27** |
| 4K Mixed 70/30 Total IOPS | **19587.8** | **20092.6** | **40395.4** | **8274.5** |


<!-- BENCHMARK_RESULTS_END -->
