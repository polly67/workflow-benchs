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
