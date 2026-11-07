# 🍏 macOS Runner GPU & Metal Diagnostic Benchmark Report

**Target Runner**: `macos-latest` (Apple Silicon VM)  
**Repository**: [`polly67/workflow-benchs`](https://github.com/polly67/workflow-benchs)  
**Workflow Run**: [#42359018382](https://github.com/polly67/workflow-benchs/actions/runs/42359018382)  
**Timestamp**: 2026-11-07T09:16:40Z  

---

## 📌 1. Host Virtual Machine Hardware Overview

| Parameter | Specification |
| :--- | :--- |
| **Model Name** | Apple Virtual Machine 1 (`VirtualMac2,1`) |
| **Chip / SoC** | Apple M2 Pro (Virtual) |
| **Host / Kernel** | Darwin Kernel Version 25.6.0 (`ARM64_VMAPPLE`) |
| **CPU Allocation** | 5 vCPUs |
| **System Memory (RAM)** | 14 GB Unified Memory |
| **Display Mode** | Headless Virtual Machine |

---

## 🎮 2. GPU & Graphics Architecture

| Parameter | Specification | Notes |
| :--- | :--- | :--- |
| **IOKit GPU Driver Class** | `AppleParavirtGPU` | Virtualized GPU interface |
| **Driver Bundle** | `com.apple.driver.AppleParavirtGPUIOGPUFamily` | Apple ARMIODevice provider |
| **Metal Device Name** | `Apple Paravirtual device` | Single active Metal device |
| **Unified Memory** | **Yes** (`true`) | Shared between CPU and GPU |
| **Max Working Set** | **9,557 MB** (~9.33 GB) | Available for GPU allocations |
| **Max Single Buffer** | **7,168 MB** (7.0 GB) | Max single Metal allocation |
| **Metal Family Support** | Paravirtual profile | Subset of Metal compute pipeline |

---

## ⚡ 3. Metal Compute & Throughput Benchmarks

| Benchmark Metric | Result | Evaluation |
| :--- | :--- | :--- |
| **Metal Kernel Compilation** | **Success** | Runtime MSL kernel compilation |
| **Vector Addition (10M floats)** | **1.21 ms** (Correctness: Passed) | Fast parallel compute dispatch |
| **Effective GPU Memory Bandwidth** | **92.35 GB/s** | High-speed paravirtual unified memory |
| **Synthetic Compute Stress** | **6.21 ms** (644.19 GFLOPS) | Heavy trigonometric & FMA compute |
| **MPS (Metal Performance Shaders)** | **Supported** | `MPSSupportsMTLDevice: true` |
| **2048x2048 FP32 GEMM Latency** | **5.04 ms** | Hardware matrix multiplication |
| **GEMM FP32 Peak Throughput** | **3.41 TFLOPS** | Outstanding virtualized tensor compute |

---

## 🔬 4. Framework Compatibility Analysis

- **Native Metal API (`Metal.framework`)**: **100% Functional**. Compute shaders, command buffers, buffer creation, and threadgroup dispatch execute cleanly.
- **Metal Performance Shaders (`MPSMatrixMultiplication`)**: **Supported & Accelerated** (3.41 TFLOPS on FP32 GEMM).
- **PyTorch (`torch.backends.mps`)**: PyTorch skips the paravirtual device with:
  > `UserWarning: Skipping device Apple Paravirtual device that does not support Metal 2.0`  
  PyTorch MPS checks for strict Apple GPU families (e.g. `apple7`, `apple8`), whereas the paravirtual driver exposes a generic virtualized Metal device. For workloads using native Metal, Swift, CoreML, or MPS C-APIs, full GPU acceleration is available.
