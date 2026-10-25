# 📊 GitHub Actions Free Runners Benchmark Comparison

Comparison of GitHub Actions standard hosted runners for public repositories (x86-64 vs ARM64).

| Metric | `ubuntu-latest` | `ubuntu-24.04-arm` | `macos-latest` | `macos-15-intel` | `self-hosted` |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **🖥️ System Specs** |  |  |  |  |  |
| Architecture | x86_64 | aarch64 | arm64 | x86_64 | x86_64 |
| OS Version | Ubuntu 24.04.5 LTS | Ubuntu 24.04.5 LTS | macOS 26.6.2 | macOS 15.7.9 | Ubuntu 24.04.5 LTS |
| Kernel | 6.17.0-1022-azure | 6.17.0-1022-azure | 25.6.0 | 24.6.0 | 6.8.0-146-generic |
| CPU Model | AMD EPYC 7763 64-Core Processor | Neoverse-N2 | Apple M1 (Virtual) | Intel(R) Core(TM) i7-8700B CPU @ 3.20GHz | AMD EPYC Processor |
| vCPUs | 4 | 4 | 3 | 4 | 4 |
| RAM Total (GB) | 15.61 | 15.57 | 7.0 | 14.0 | 7.76 |
| Disk Total (GB) | 144.26 | 144.26 | 319.51 | 324.68 | 55.81 |
| Disk Free (GB) | 85.36 | 107.32 | 96.43 | 108.42 | 11.87 |
| **🧠 CPU Performance** |  |  |  |  |  |
| Sysbench Single-Thread (events/s) | **1441.57** | **1498.25** | **7971487.14** | **3864385.17** | **1356.95** |
| Sysbench Single-Thread Avg Latency (ms) | 0.69 | 0.67 | 0.0 | 0.0 | 0.74 |
| Sysbench Multi-Thread (events/s) | **3148.47** | **5947.64** | **20422345.75** | **12170578.96** | **5352.06** |
| Sysbench Multi-Thread Avg Latency (ms) | 1.27 | 0.67 | 0.0 | 0.0 | 0.75 |
| SHA256 Throughput (MB/s) | **1499.94** | **2048.44** | **1972.16** | **381.68** | **1425.62** |
| **💾 Memory Bandwidth** |  |  |  |  |  |
| Sysbench Mem Read (MiB/s) | **99749.67** | **113663.12** | **47255.98** | **93568.96** | **129848.34** |
| Sysbench Mem Write (MiB/s) | **45690.64** | **106696.49** | **40760.03** | **54190.5** | **30754.95** |
| **🚀 Disk IOPS & Throughput (fio)** |  |  |  |  |  |
| 4K Random Read IOPS | **19548.5** | **18551.0** | **42149.5** | **10190.8** | **504.9** |
| 4K Random Read Latency (ms) | 3.267 | 3.447 | 0.328 | 1.386 | 126.698 |
| 4K Random Read Bandwidth (MB/s) | 76.36 | 72.46 | 164.65 | 39.81 | 1.97 |
| 4K Random Write IOPS | **19646.3** | **19188.9** | **23870.2** | **9034.5** | **504.3** |
| 4K Random Write Latency (ms) | 3.25 | 3.332 | 0.585 | 1.524 | 126.786 |
| 4K Random Write Bandwidth (MB/s) | 76.74 | 74.96 | 93.24 | 35.29 | 1.97 |
| 1M Sequential Read (MB/s) | **405.48** | **361.32** | **8258.95** | **3969.21** | **462.19** |
| 1M Sequential Write (MB/s) | **405.32** | **317.97** | **6968.91** | **3872.26** | **374.49** |
| 4K Mixed 70/30 Total IOPS | **19583.9** | **19544.0** | **33505.0** | **10972.0** | **996.4** |
