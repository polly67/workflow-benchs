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
