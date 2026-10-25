# 📊 GitHub Actions Free Runners Benchmark Comparison

Comparison of GitHub Actions standard hosted runners for public repositories (x86-64 vs ARM64).

| Metric | `ubuntu-latest` | `ubuntu-24.04-arm` | `macos-latest` | `macos-15-intel` | `self-hosted` |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **🖥️ System Specs** |  |  |  |  |  |
| Architecture | x86_64 | aarch64 | arm64 | x86_64 | x86_64 |
| OS Version | Ubuntu 24.04.5 LTS | Ubuntu 24.04.5 LTS | macOS 26.6.2 | macOS 15.7.9 | Ubuntu 24.04.5 LTS |
| Kernel | 6.17.0-1022-azure | 6.17.0-1022-azure | 25.6.0 | 24.6.0 | 6.8.0-146-generic |
| CPU Model | AMD EPYC 9V45 96-Core Processor | Neoverse-N2 | Apple M1 (Virtual) | Intel(R) Core(TM) i7-8700B CPU @ 3.20GHz | AMD EPYC Processor |
| vCPUs | 4 | 4 | 3 | 4 | 4 |
| RAM Total (GB) | 15.61 | 15.57 | 7.0 | 14.0 | 7.76 |
| Disk Total (GB) | 144.26 | 144.26 | 319.51 | 324.68 | 55.81 |
| Disk Free (GB) | 85.36 | 107.32 | 96.22 | 108.41 | 11.89 |
| **🧠 CPU Performance** |  |  |  |  |  |
| Sysbench Single-Thread (events/s) | **1993.61** | **1499.22** | **8460121.49** | **3442330.88** | **1358.18** |
| Sysbench Single-Thread Avg Latency (ms) | 0.5 | 0.67 | 0.0 | 0.0 | 0.74 |
| Sysbench Multi-Thread (events/s) | **4122.29** | **5965.64** | **23300374.41** | **10160445.05** | **5345.91** |
| Sysbench Multi-Thread Avg Latency (ms) | 0.97 | 0.67 | 0.0 | 0.0 | 0.75 |
| SHA256 Throughput (MB/s) | **1981.21** | **2050.0** | **2149.58** | **410.21** | **1425.88** |
| **💾 Memory Bandwidth** |  |  |  |  |  |
| Sysbench Mem Read (MiB/s) | **196816.13** | **60422.5** | **62086.53** | **69581.76** | **136063.49** |
| Sysbench Mem Write (MiB/s) | **63152.73** | **105440.35** | **43008.18** | **38478.3** | **34070.3** |
| **🚀 Disk IOPS & Throughput (fio)** |  |  |  |  |  |
| 4K Random Read IOPS | **19948.8** | **18260.8** | **28802.6** | **8458.9** | **504.9** |
| 4K Random Read Latency (ms) | 3.204 | 3.502 | 0.517 | 1.713 | 126.701 |
| 4K Random Read Bandwidth (MB/s) | 77.93 | 71.33 | 112.51 | 33.04 | 1.97 |
| 4K Random Write IOPS | **20029.0** | **19433.1** | **24382.1** | **6555.7** | **504.7** |
| 4K Random Write Latency (ms) | 3.19 | 3.29 | 0.62 | 2.221 | 126.716 |
| 4K Random Write Bandwidth (MB/s) | 78.24 | 75.91 | 95.24 | 25.61 | 1.97 |
| 1M Sequential Read (MB/s) | **398.76** | **341.31** | **9670.37** | **2738.3** | **400.68** |
| 1M Sequential Write (MB/s) | **268.15** | **318.53** | **8470.11** | **2142.29** | **336.35** |
| 4K Mixed 70/30 Total IOPS | **20109.1** | **19532.2** | **49929.1** | **6737.0** | **998.9** |
