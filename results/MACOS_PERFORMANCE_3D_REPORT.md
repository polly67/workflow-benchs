# 📊 macOS Runner Comprehensive Benchmark: CPU, Disk IOPS & GPU 3D Render

**Target Runner**: `macos-latest` (Apple Silicon VM)  
**Repository**: [`polly67/workflow-benchs`](https://github.com/polly67/workflow-benchs)  
**Workflow Run**: [#42359387344](https://github.com/polly67/workflow-benchs/actions/runs/42359387344)  
**Execution Timestamp**: 2026-11-07T09:21:44Z  

---

## 💽 1. Disk IOPS & Storage Performance (`fio`)

Measured using POSIX AIO on NVMe-backed host storage (`iodepth=64`, `direct=1`):

| Test Metric | Value | Latency | Evaluation |
| :--- | :--- | :--- | :--- |
| **4K Random Read IOPS** | **52,071.99 IOPS** (203.41 MB/s) | **0.278 ms** | 🚀 High IOPS NVMe read |
| **4K Random Write IOPS** | **22,952.51 IOPS** (89.66 MB/s) | **0.647 ms** | ⚡ Sub-millisecond write latency |
| **4K Mixed 70/30 R/W IOPS** | **34,788.28 IOPS** | — | Balanced transactional workload |
| **1M Sequential Read** | **9,287.21 MB/s** (~9.3 GB/s) | — | Host PCIe 4.0/Apple NVMe speed |
| **1M Sequential Write** | **7,709.41 MB/s** (~7.7 GB/s) | — | Massive write throughput |

---

## 🧠 2. CPU Speed & Memory Subsystem (`sysbench`)

| Test Metric | Result | Notes |
| :--- | :--- | :--- |
| **Single-Thread Speed** | **8,481,038.81 eps** | Apple Silicon high-IPC performance core |
| **Multi-Thread Speed** | **24,696,685.00 eps** | Linear scaling across 3 vCPUs |
| **Cryptographic Throughput** | **1,977.48 MB/s** | Hardware-accelerated SHA-256 |
| **Memory Read Throughput** | **41,737.32 MiB/s** (~40.8 GB/s) | LPDDR5 unified memory interface |
| **Memory Write Throughput** | **49,849.32 MiB/s** (~48.7 GB/s) | High write bandwidth |

---

## 🎮 3. GPU 3D Offscreen Rendering (Metal Pipeline)

Tested with a complete 3D rasterization pipeline (Vertex Shader, Blinn-Phong Fragment Shader, 32-bit Depth Buffer, MVP Perspective Transformation):

| 3D Render Metric | Result | Status |
| :--- | :--- | :--- |
| **Render Target** | **1920 × 1080 (1080p Full HD)** | Offscreen shared texture |
| **3D Scene Geometry** | **3,200 triangles** (UV-Sphere mesh) | Animated rotation per frame |
| **Total Frames Rendered** | **300 frames** | Rendered in 0.304s |
| **Average Frame Rate** | **987.48 FPS** | Ultra-high offscreen rasterization |
| **Frame Latency** | **1.01 ms / frame** | Real-time 3D rendering |
| **Polygon Throughput** | **3.16 Million Triangles / sec** | High-throughput vertex transform |
| **Rasterization Verification** | **VERIFIED (`true`)** | Pixel readback confirms shaded geometry |

---

## ⚡ 4. GPU Compute & Tensor Performance

| Compute Metric | Result | Notes |
| :--- | :--- | :--- |
| **GPU Memory Bandwidth** | **43.79 GB/s** | Metal shared buffer vector add |
| **Trigonometric / FMA Compute** | **559.33 GFLOPS** | Synthetic parallel compute shader |
| **MPS 2048×2048 FP32 GEMM** | **12.53 ms (1.37 TFLOPS)** | MetalPerformanceShaders matrix multiplication |
