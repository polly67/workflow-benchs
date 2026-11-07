#!/usr/bin/env python3
import json
import os
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path

def run_cmd(cmd, timeout=180):
    try:
        res = subprocess.run(cmd, shell=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except Exception as e:
        return -1, "", str(e)

def bench_sha256():
    print("Testing SHA-256 computation throughput...")
    import hashlib
    data = b"0" * 1024 * 1024
    start = time.time()
    for _ in range(100):
        hashlib.sha256(data).digest()
    elapsed = time.time() - start
    mb_per_sec = round(100.0 / elapsed, 2)
    return {"sha256_mb_per_sec": mb_per_sec, "time_sec": round(elapsed, 4)}

def bench_cpu_sysbench():
    print("Testing CPU performance with sysbench...")
    results = {}
    if not shutil.which("sysbench"):
        return {"error": "sysbench not installed"}

    # Single-thread
    _, out_st, _ = run_cmd("sysbench cpu --cpu-max-prime=20000 --threads=1 --time=10 run")
    for line in out_st.splitlines():
        if "events per second:" in line:
            results["single_thread_eps"] = float(line.split(":")[1].strip())
        elif "avg:" in line and "Latency" not in line:
            parts = line.split()
            if len(parts) >= 2:
                try:
                    results["single_thread_lat_ms"] = float(parts[1])
                except ValueError:
                    pass

    # Multi-thread
    cores = os.cpu_count() or 1
    _, out_mt, _ = run_cmd(f"sysbench cpu --cpu-max-prime=20000 --threads={cores} --time=10 run")
    for line in out_mt.splitlines():
        if "events per second:" in line:
            results["multi_thread_eps"] = float(line.split(":")[1].strip())
        elif "avg:" in line and "Latency" not in line:
            parts = line.split()
            if len(parts) >= 2:
                try:
                    results["multi_thread_lat_ms"] = float(parts[1])
                except ValueError:
                    pass

    # Memory throughput
    _, out_mem_r, _ = run_cmd(f"sysbench memory --threads={cores} --memory-block-size=1M --memory-total-size=10G --memory-oper=read run")
    for line in out_mem_r.splitlines():
        if "transferred (" in line and "MiB/sec" in line:
            results["memory_read_mib_sec"] = float(line.split("(")[1].split("MiB/sec")[0].strip())

    _, out_mem_w, _ = run_cmd(f"sysbench memory --threads={cores} --memory-block-size=1M --memory-total-size=10G --memory-oper=write run")
    for line in out_mem_w.splitlines():
        if "transferred (" in line and "MiB/sec" in line:
            results["memory_write_mib_sec"] = float(line.split("(")[1].split("MiB/sec")[0].strip())

    return results

def run_fio_job(name, rw, bs, iodepth, direct, test_file, runtime=8):
    ioengine = "posixaio" if platform.system() == "Darwin" else "libaio"
    cmd = (
        f"fio --name={name} --ioengine={ioengine} --iodepth={iodepth} "
        f"--rw={rw} --bs={bs} --direct={direct} --size=1G --runtime={runtime} "
        f"--time_based=1 --output-format=json --filename={test_file}"
    )
    code, out, err = run_cmd(cmd, timeout=runtime + 30)
    if code != 0 or not out:
        return None
    try:
        data = json.loads(out)
        return data["jobs"][0]
    except Exception:
        return None

def bench_disk_fio():
    print("Testing Disk IOPS and throughput with fio...")
    if not shutil.which("fio"):
        return {"error": "fio not installed"}

    target = "./fio_bench_target.dat"
    results = {}
    try:
        # 4K Random Read
        print("  - Running 4K Random Read IOPS test...")
        job = run_fio_job("randread_4k", "randread", "4k", 64, 1, target)
        if job:
            read_sec = job["read"]
            results["randread_4k_iops"] = read_sec["iops"]
            results["randread_4k_bw_mb_s"] = round(read_sec["bw"] / 1024, 2)
            results["randread_4k_lat_ms"] = round(read_sec["lat_ns"]["mean"] / 1e6, 3)

        # 4K Random Write
        print("  - Running 4K Random Write IOPS test...")
        job = run_fio_job("randwrite_4k", "randwrite", "4k", 64, 1, target)
        if job:
            write_sec = job["write"]
            results["randwrite_4k_iops"] = write_sec["iops"]
            results["randwrite_4k_bw_mb_s"] = round(write_sec["bw"] / 1024, 2)
            results["randwrite_4k_lat_ms"] = round(write_sec["lat_ns"]["mean"] / 1e6, 3)

        # 1M Sequential Read
        print("  - Running 1M Sequential Read throughput test...")
        job = run_fio_job("seqread_1m", "read", "1m", 16, 1, target)
        if job:
            read_sec = job["read"]
            results["seqread_1m_bw_mb_s"] = round(read_sec["bw"] / 1024, 2)
            results["seqread_1m_iops"] = read_sec["iops"]

        # 1M Sequential Write
        print("  - Running 1M Sequential Write throughput test...")
        job = run_fio_job("seqwrite_1m", "write", "1m", 16, 1, target)
        if job:
            write_sec = job["write"]
            results["seqwrite_1m_bw_mb_s"] = round(write_sec["bw"] / 1024, 2)
            results["seqwrite_1m_iops"] = write_sec["iops"]

        # 4K Mixed 70/30
        print("  - Running 4K Mixed 70/30 Read/Write test...")
        job = run_fio_job("mixed_4k", "randrw", "4k", 64, 1, target)
        if job:
            results["mixed_4k_read_iops"] = job["read"]["iops"]
            results["mixed_4k_write_iops"] = job["write"]["iops"]
            results["mixed_4k_total_iops"] = round(job["read"]["iops"] + job["write"]["iops"], 2)

    finally:
        if os.path.exists(target):
            try:
                os.remove(target)
            except Exception:
                pass

    return results

def main():
    print("=" * 60)
    print("🚀 macOS Comprehensive Benchmark: Disk IOPS, CPU Speed & GPU 3D Render")
    print("=" * 60)

    summary = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "os": platform.platform(),
        "cpu_count": os.cpu_count() or 1,
        "cpu": {},
        "sha256": {},
        "disk_iops": {},
        "gpu_compute": {},
        "gpu_3d_render": {}
    }

    # 1. CPU & SHA256 Benchmarks
    print("\n[Step 1/3] Benchmarking CPU Speed & Cryptographic Throughput...")
    summary["sha256"] = bench_sha256()
    summary["cpu"] = bench_cpu_sysbench()

    # 2. Disk IOPS Benchmarks
    print("\n[Step 2/3] Benchmarking Disk IOPS & Latency with fio...")
    summary["disk_iops"] = bench_disk_fio()

    # 3. GPU Metal 3D Render & Compute Benchmarks
    print("\n[Step 3/3] Benchmarking GPU 3D Render & Metal Compute...")
    scripts_dir = Path(__file__).parent

    # Swift 3D Render
    swift_3d_script = scripts_dir / "gpu_3d_render.swift"
    if swift_3d_script.exists():
        print("Running Swift Metal 3D Offscreen Rendering benchmark...")
        code, out, err = run_cmd(f"swift {swift_3d_script}")
        print(out)
        if err:
            print(f"3D Render stderr: {err}")
        render_json = Path("results/metal_3d_render_report.json")
        if render_json.exists():
            try:
                with open(render_json, "r") as f:
                    summary["gpu_3d_render"] = json.load(f)
            except Exception as e:
                summary["gpu_3d_render"] = {"error": str(e)}

    # Swift Metal Compute & MPS
    swift_compute_script = scripts_dir / "gpu_test.swift"
    if swift_compute_script.exists():
        print("Running Swift Metal Compute & MPS Matrix Multiplication benchmark...")
        code, out, err = run_cmd(f"swift {swift_compute_script}")
        print(out)
        compute_json = Path("results/metal_report.json")
        if compute_json.exists():
            try:
                with open(compute_json, "r") as f:
                    summary["gpu_compute"] = json.load(f)
            except Exception as e:
                summary["gpu_compute"] = {"error": str(e)}

    # Write summary
    os.makedirs("results", exist_ok=True)
    summary_path = "results/macos-full-benchmark.json"
    with open(summary_path, "w") as f:
        json.dump(summary, f, indent=2)

    print("\n" + "=" * 60)
    print(f"🎉 All Benchmarks Complete! Saved to {summary_path}")
    print("=" * 60)

if __name__ == "__main__":
    main()
