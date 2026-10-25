# 📊 GitHub Actions Free Runners Benchmark Comparison

Comparison of GitHub Actions standard hosted runners for public repositories (x86-64 vs ARM64).

| Metric | `ubuntu-latest` | `ubuntu-24.04-arm` | `macos-latest` | `macos-15-intel` | `self-hosted` |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **🖥️ System Specs** |  |  |  |  |  |
| Architecture | x86_64 | aarch64 | arm64 | x86_64 | x86_64 |
| OS Version | Ubuntu 24.04.5 LTS | Ubuntu 24.04.5 LTS | macOS 26.6.2 | macOS 15.7.9 | Ubuntu 24.04.5 LTS |
| Kernel | 6.17.0-1022-azure | 6.17.0-1022-azure | 25.6.0 | 24.6.0 | 6.8.0-146-generic |
| CPU Model | AMD EPYC 7763 64-Core Processor | Neoverse-N2 | Apple M2 Pro (Virtual) | Intel(R) Core(TM) i7-8700B CPU @ 3.20GHz | AMD EPYC Processor |
| vCPUs | 4 | 4 | 5 | 4 | 4 |
| RAM Total (GB) | 15.61 | 15.57 | 14.0 | 14.0 | 7.76 |
| Disk Total (GB) | 144.26 | 144.26 | 319.51 | 324.68 | 55.81 |
| Disk Free (GB) | 85.37 | 107.32 | 96.42 | 108.42 | 11.48 |
| **🧠 CPU Performance** |  |  |  |  |  |
| Sysbench Single-Thread (events/s) | **1439.07** | **1498.52** | **10257126.07** | **4007650.5** | **1349.15** |
| Sysbench Single-Thread Avg Latency (ms) | 0.69 | 0.67 | 0.0 | 0.0 | 0.74 |
| Sysbench Multi-Thread (events/s) | **3153.15** | **5960.75** | **48298167.25** | **15160914.52** | **5364.83** |
| Sysbench Multi-Thread Avg Latency (ms) | 1.27 | 0.67 | 0.0 | 0.0 | 0.74 |
| SHA256 Throughput (MB/s) | **1504.23** | **2032.54** | **2289.72** | **525.35** | **1371.96** |
| **💾 Memory Bandwidth** |  |  |  |  |  |
| Sysbench Mem Read (MiB/s) | **96549.03** | **81052.86** | **120733.36** | **112144.21** | **159739.11** |
| Sysbench Mem Write (MiB/s) | **44126.93** | **108217.59** | **81203.46** | **79255.74** | **28701.37** |
| **🚀 Disk IOPS & Throughput (fio)** |  |  |  |  |  |
| 4K Random Read IOPS | **19636.2** | **19980.0** | **64390.3** | **10379.2** | **504.9** |
| 4K Random Read Latency (ms) | 3.252 | 3.2 | 0.2 | 1.44 | 126.7 |
| 4K Random Read Bandwidth (MB/s) | 76.7 | 78.05 | 251.52 | 40.54 | 1.97 |
| 4K Random Write IOPS | **19597.8** | **20109.7** | **42985.4** | **9365.5** | **502.4** |
| 4K Random Write Latency (ms) | 3.26 | 3.18 | 0.339 | 1.418 | 127.31 |
| 4K Random Write Bandwidth (MB/s) | 76.55 | 78.55 | 167.91 | 36.58 | 1.96 |
| 1M Sequential Read (MB/s) | **405.11** | **404.67** | **16577.04** | **3980.16** | **320.06** |
| 1M Sequential Write (MB/s) | **405.19** | **343.39** | **17645.54** | **4069.38** | **373.33** |
| 4K Mixed 70/30 Total IOPS | **19609.4** | **20096.7** | **58613.7** | **10639.8** | **993.8** |
