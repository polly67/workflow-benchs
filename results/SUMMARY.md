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
| Disk Free (GB) | 96.07 | 107.32 | 85.37 |
| **🧠 CPU Performance** |  |  |  |
| Sysbench Single-Thread (events/s) | **9256888.07** | **1498.26** | **1440.82** |
| Sysbench Single-Thread Avg Latency (ms) | 0.0 | 0.67 | 0.69 |
| Sysbench Multi-Thread (events/s) | **27840292.68** | **5973.69** | **3154.33** |
| Sysbench Multi-Thread Avg Latency (ms) | 0.0 | 0.67 | 1.27 |
| SHA256 Throughput (MB/s) | **2246.04** | **2044.11** | **1506.23** |
| **💾 Memory Bandwidth** |  |  |  |
| Sysbench Mem Read (MiB/s) | **64077.85** | **93442.83** | **99129.32** |
| Sysbench Mem Write (MiB/s) | **65255.63** | **106086.65** | **47919.66** |
| **🚀 Disk IOPS & Throughput (fio)** |  |  |  |
| 4K Random Read IOPS | **65932.7** | **19372.9** | **19548.5** |
| 4K Random Read Latency (ms) | 0.218 | 3.301 | 3.268 |
| 4K Random Read Bandwidth (MB/s) | 257.55 | 75.68 | 76.36 |
| 4K Random Write IOPS | **27731.6** | **19939.4** | **19571.1** |
| 4K Random Write Latency (ms) | 0.534 | 3.207 | 3.263 |
| 4K Random Write Bandwidth (MB/s) | 108.33 | 77.89 | 76.45 |
| 1M Sequential Read (MB/s) | **10510.85** | **372.54** | **405.16** |
| 1M Sequential Write (MB/s) | **7924.02** | **325.34** | **406.04** |
| 4K Mixed 70/30 Total IOPS | **29171.2** | **19527.0** | **19649.8** |
