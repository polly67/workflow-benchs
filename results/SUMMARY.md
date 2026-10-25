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
