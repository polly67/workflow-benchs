#!/usr/bin/env python3
import json
import os
import platform
import subprocess
import sys
import time

def run_cmd(cmd, check=False):
    try:
        res = subprocess.run(cmd, shell=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except Exception as e:
        return -1, "", str(e)

def main():
    print("=" * 60)
    print("🍏 macOS GPU Inspection & Comprehensive Benchmark Suite")
    print("=" * 60)

    results = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "os_info": {
            "system": platform.system(),
            "release": platform.release(),
            "version": platform.version(),
            "machine": platform.machine(),
            "processor": platform.processor(),
        },
        "system_profiler_hardware": "",
        "system_profiler_displays": "",
        "metal_results": {},
        "pytorch_mps": {}
    }

    # 1. Hardware Profiler
    print("\n--- 1. Querying SPHardwareDataType ---")
    code, out, err = run_cmd("system_profiler SPHardwareDataType")
    if code == 0:
        print(out)
        results["system_profiler_hardware"] = out
    else:
        print(f"Error querying hardware: {err}")

    # 2. Displays / Graphics Profiler
    print("\n--- 2. Querying SPDisplaysDataType ---")
    code, out, err = run_cmd("system_profiler SPDisplaysDataType")
    if code == 0:
        print(out)
        results["system_profiler_displays"] = out
    else:
        print(f"Error querying displays: {err}")

    # 3. Swift Metal Test
    print("\n--- 3. Running Swift Metal Benchmark ---")
    swift_script = os.path.join(os.path.dirname(__file__), "gpu_test.swift")
    if os.path.exists(swift_script):
        code, out, err = run_cmd(f"swift {swift_script}")
        print(out)
        if err:
            print(f"Swift stderr: {err}")
        
        metal_json_path = "results/metal_report.json"
        if os.path.exists(metal_json_path):
            try:
                with open(metal_json_path, "r") as f:
                    results["metal_results"] = json.load(f)
            except Exception as e:
                results["metal_results"] = {"error": str(e)}
    else:
        print("Swift script not found.")

    # 4. PyTorch MPS Test
    print("\n--- 4. PyTorch & Metal Performance Shaders (MPS) Test ---")
    try:
        import torch
        pytorch_info = {
            "torch_version": torch.__version__,
            "mps_built": torch.backends.mps.is_built(),
            "mps_available": torch.backends.mps.is_available(),
        }
        print(f"PyTorch version: {torch.__version__}")
        print(f"MPS Built: {pytorch_info['mps_built']}")
        print(f"MPS Available: {pytorch_info['mps_available']}")

        if torch.backends.mps.is_available():
            device = torch.device("mps")
            print("Allocating tensor on MPS...")
            start = time.time()
            a = torch.randn(2048, 2048, device=device, dtype=torch.float32)
            b = torch.randn(2048, 2048, device=device, dtype=torch.float32)
            torch.mps.synchronize()
            
            # GEMM benchmark
            runs = 10
            start = time.time()
            for _ in range(runs):
                c = torch.matmul(a, b)
            torch.mps.synchronize()
            elapsed = (time.time() - start) / runs
            
            # 2 * M * N * K
            tflops = (2.0 * (2048 ** 3)) / elapsed / 1e12
            print(f"PyTorch MPS GEMM 2048x2048: {elapsed*1000:.2f} ms ({tflops:.2f} TFLOPS)")
            pytorch_info["gemm_latency_ms"] = elapsed * 1000
            pytorch_info["gemm_tflops"] = tflops
            pytorch_info["success"] = True
        else:
            pytorch_info["success"] = False

        results["pytorch_mps"] = pytorch_info
    except ImportError:
        print("PyTorch not installed in this environment.")
        results["pytorch_mps"] = {"error": "PyTorch not installed"}
    except Exception as e:
        print(f"PyTorch test error: {e}")
        results["pytorch_mps"] = {"error": str(e)}

    # Save consolidated results
    os.makedirs("results", exist_ok=True)
    out_file = "results/macos-gpu-test.json"
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\n✅ Consolidated GPU test results written to {out_file}")

if __name__ == "__main__":
    main()
