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
