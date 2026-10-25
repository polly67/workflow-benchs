#!/usr/bin/env python3
"""
GitHub Actions Runner Benchmark Script
Measures:
- CPU: Single & Multi-thread Sysbench, SHA256 computation
- Memory: Read & Write throughput with Sysbench
- Disk: FIO 4K Random Read/Write IOPS, Latency, and 1M Sequential Throughput
"""

import os
import sys
import json
import time
import shutil
import hashlib
import platform
import subprocess
from pathlib import Path

def run_cmd(cmd, timeout=120):
    """Execute command and return stdout string."""
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return res.stdout.strip()
    except Exception as e:
        return f"Error: {e}"

def get_sys_info():
    uname = platform.uname()
    arch = uname.machine
    system = uname.system
    kernel = uname.release
    cpu_count = os.cpu_count() or 1

    # CPU Model
    cpu_model = "Unknown"
    if os.path.exists("/proc/cpuinfo"):
        with open("/proc/cpuinfo", "r") as f:
            for line in f:
                if "model name" in line:
                    cpu_model = line.split(":", 1)[1].strip()
                    break
                elif "Hardware" in line or "Model" in line or "Processor" in line:
                    cpu_model = line.split(":", 1)[1].strip()

    if cpu_model == "Unknown" and shutil.which("lscpu"):
        lscpu_out = run_cmd("lscpu")
        for line in lscpu_out.splitlines():
            if line.startswith("Model name:"):
                cpu_model = line.split(":", 1)[1].strip()
                break
            elif line.startswith("BIOS Model name:"):
                cpu_model = line.split(":", 1)[1].strip()
                break

    # Memory
    mem_total_gb = 0.0
    mem_avail_gb = 0.0
    if os.path.exists("/proc/meminfo"):
        with open("/proc/meminfo", "r") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    mem_total_gb = round(int(line.split()[1]) / (1024 * 1024), 2)
                elif line.startswith("MemAvailable:"):
                    mem_avail_gb = round(int(line.split()[1]) / (1024 * 1024), 2)

    # Disk
    disk = shutil.disk_usage("/")
    disk_total_gb = round(disk.total / (1024**3), 2)
    disk_free_gb = round(disk.free / (1024**3), 2)

    # OS name
    os_name = "Linux"
    if os.path.exists("/etc/os-release"):
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    os_name = line.strip().split("=", 1)[1].strip('"')

    return {
        "os_name": os_name,
        "kernel": kernel,
        "arch": arch,
        "cpu_model": cpu_model,
        "cpu_cores": cpu_count,
        "mem_total_gb": mem_total_gb,
        "mem_avail_gb": mem_avail_gb,
        "disk_total_gb": disk_total_gb,
        "disk_free_gb": disk_free_gb
    }

def bench_sha256():
    """Deterministic hashing test (50MB of sha256 chunks)."""
    data = b"0" * 1024 * 1024  # 1MB
    start = time.time()
    for _ in range(50):
        hashlib.sha256(data).digest()
    elapsed = time.time() - start
    mb_per_sec = round(50.0 / elapsed, 2)
    return {"sha256_mb_per_sec": mb_per_sec, "time_sec": round(elapsed, 3)}

def bench_sysbench_cpu():
    """Run sysbench CPU single and multi-thread."""
    results = {}
    if not shutil.which("sysbench"):
        return {"error": "sysbench not installed"}

    # Single-thread
    cmd_st = "sysbench cpu --cpu-max-prime=20000 --threads=1 --time=10 run"
    st_out = run_cmd(cmd_st)
    for line in st_out.splitlines():
        if "events per second:" in line:
            results["single_thread_eps"] = float(line.split(":")[1].strip())
        elif "avg:" in line and "Latency" not in line:
            parts = line.split()
            if len(parts) >= 2:
                try:
                    results["single_thread_lat_avg_ms"] = float(parts[1])
                except ValueError:
                    pass

    # Multi-thread (all cores)
    cores = os.cpu_count() or 1
    cmd_mt = f"sysbench cpu --cpu-max-prime=20000 --threads={cores} --time=10 run"
    mt_out = run_cmd(cmd_mt)
    for line in mt_out.splitlines():
        if "events per second:" in line:
            results["multi_thread_eps"] = float(line.split(":")[1].strip())
        elif "avg:" in line and "Latency" not in line:
            parts = line.split()
            if len(parts) >= 2:
                try:
                    results["multi_thread_lat_avg_ms"] = float(parts[1])
                except ValueError:
                    pass

    return results

def bench_sysbench_memory():
    """Run sysbench memory read and write benchmarks."""
    results = {}
    if not shutil.which("sysbench"):
        return {"error": "sysbench not installed"}

    cores = os.cpu_count() or 1

    # Memory Read
    cmd_read = f"sysbench memory --threads={cores} --memory-block-size=1M --memory-total-size=10G --memory-oper=read run"
    read_out = run_cmd(cmd_read)
    for line in read_out.splitlines():
        if "transferred (" in line and "MiB/sec" in line:
            # e.g.: 10240.00 MiB transferred (25432.12 MiB/sec)
            val = line.split("(")[1].split("MiB/sec")[0].strip()
            results["mem_read_mib_sec"] = float(val)

    # Memory Write
    cmd_write = f"sysbench memory --threads={cores} --memory-block-size=1M --memory-total-size=10G --memory-oper=write run"
    write_out = run_cmd(cmd_write)
    for line in write_out.splitlines():
        if "transferred (" in line and "MiB/sec" in line:
            val = line.split("(")[1].split("MiB/sec")[0].strip()
            results["mem_write_mib_sec"] = float(val)

    return results

def run_fio_job(name, rw, bs, iodepth, direct, test_file, runtime=10):
    cmd = [
        "fio", f"--name={name}", "--ioengine=libaio", f"--iodepth={iodepth}",
        f"--rw={rw}", f"--bs={bs}", f"--direct={direct}", "--size=1G",
        f"--runtime={runtime}", "--time_based=1", "--output-format=json",
        f"--filename={test_file}"
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=runtime + 30)
        data = json.loads(res.stdout)
        job = data["jobs"][0]
        return job
    except Exception as e:
        print(f"Error running fio job {name}: {e}")
        return None

def bench_fio_disk():
    """Run comprehensive fio disk IOPS and bandwidth benchmarks."""
    if not shutil.which("fio"):
        return {"error": "fio not installed"}

    test_file = Path("./fio_benchmark_target.dat")
    results = {}

    try:
        # 1. Random 4K Read (IOPS)
        job_randread = run_fio_job("randread_4k", "randread", "4k", 64, 1, test_file, runtime=10)
        if job_randread:
            read_data = job_randread["read"]
            results["randread_4k_iops"] = round(read_data["iops"], 1)
            results["randread_4k_bw_mb_s"] = round(read_data["bw_bytes"] / (1024 * 1024), 2)
            results["randread_4k_lat_ms"] = round(read_data["clat_ns"]["mean"] / 1e6, 3)

        # 2. Random 4K Write (IOPS)
        job_randwrite = run_fio_job("randwrite_4k", "randwrite", "4k", 64, 1, test_file, runtime=10)
        if job_randwrite:
            write_data = job_randwrite["write"]
            results["randwrite_4k_iops"] = round(write_data["iops"], 1)
            results["randwrite_4k_bw_mb_s"] = round(write_data["bw_bytes"] / (1024 * 1024), 2)
            results["randwrite_4k_lat_ms"] = round(write_data["clat_ns"]["mean"] / 1e6, 3)

        # 3. Sequential 1M Read (Throughput)
        job_seqread = run_fio_job("seqread_1m", "read", "1m", 16, 1, test_file, runtime=10)
        if job_seqread:
            read_data = job_seqread["read"]
            results["seqread_1m_bw_mb_s"] = round(read_data["bw_bytes"] / (1024 * 1024), 2)
            results["seqread_1m_iops"] = round(read_data["iops"], 1)

        # 4. Sequential 1M Write (Throughput)
        job_seqwrite = run_fio_job("seqwrite_1m", "write", "1m", 16, 1, test_file, runtime=10)
        if job_seqwrite:
            write_data = job_seqwrite["write"]
            results["seqwrite_1m_bw_mb_s"] = round(write_data["bw_bytes"] / (1024 * 1024), 2)
            results["seqwrite_1m_iops"] = round(write_data["iops"], 1)

        # 5. Mixed Random 70/30 (4K IOPS)
        job_mixed = run_fio_job("mixed_70_30", "randrw", "4k", 64, 1, test_file, runtime=10)
        if job_mixed:
            r_iops = job_mixed["read"]["iops"]
            w_iops = job_mixed["write"]["iops"]
            results["mixed_4k_read_iops"] = round(r_iops, 1)
            results["mixed_4k_write_iops"] = round(w_iops, 1)
            results["mixed_4k_total_iops"] = round(r_iops + w_iops, 1)

    finally:
        if test_file.exists():
            try:
                test_file.unlink()
            except Exception:
                pass

    return results

def format_summary_markdown(runner_label, data):
    sys_info = data["sys_info"]
    cpu = data.get("cpu", {})
    mem = data.get("memory", {})
    disk = data.get("disk", {})
    sha = data.get("sha256", {})

    lines = [
        f"## ⚡ Benchmark Results: `{runner_label}`",
        "",
        "### 🖥️ System & Hardware",
        f"- **OS**: {sys_info['os_name']} ({sys_info['kernel']})",
        f"- **Architecture**: `{sys_info['arch']}`",
        f"- **CPU Model**: `{sys_info['cpu_model']}` ({sys_info['cpu_cores']} vCPUs)",
        f"- **RAM**: {sys_info['mem_total_gb']} GB total ({sys_info['mem_avail_gb']} GB available)",
        f"- **Root Disk**: {sys_info['disk_total_gb']} GB total ({sys_info['disk_free_gb']} GB free)",
        "",
        "### 🧠 CPU & Compute Performance",
        "| Metric | Result | Unit |",
        "| :--- | :--- | :--- |",
        f"| Sysbench CPU (Single-Thread) | **{cpu.get('single_thread_eps', 'N/A')}** | events/sec |",
        f"| Sysbench CPU Single-Thread Avg Latency | **{cpu.get('single_thread_lat_avg_ms', 'N/A')}** | ms |",
        f"| Sysbench CPU (Multi-Thread, {sys_info['cpu_cores']} vCPUs) | **{cpu.get('multi_thread_eps', 'N/A')}** | events/sec |",
        f"| Sysbench CPU Multi-Thread Avg Latency | **{cpu.get('multi_thread_lat_avg_ms', 'N/A')}** | ms |",
        f"| Python SHA256 Hashing | **{sha.get('sha256_mb_per_sec', 'N/A')}** | MB/s |",
        "",
        "### 💾 Memory Bandwidth",
        "| Metric | Throughput |",
        "| :--- | :--- |",
        f"| Sysbench Memory Read | **{mem.get('mem_read_mib_sec', 'N/A')} MiB/s** |",
        f"| Sysbench Memory Write | **{mem.get('mem_write_mib_sec', 'N/A')} MiB/s** |",
        "",
        "### 🚀 Disk IOPS & Throughput (fio)",
        "| Test | IOPS | Throughput | Avg Latency |",
        "| :--- | :--- | :--- | :--- |",
        f"| **4K Random Read** | `{disk.get('randread_4k_iops', 'N/A')}` IOPS | {disk.get('randread_4k_bw_mb_s', 'N/A')} MB/s | {disk.get('randread_4k_lat_ms', 'N/A')} ms |",
        f"| **4K Random Write** | `{disk.get('randwrite_4k_iops', 'N/A')}` IOPS | {disk.get('randwrite_4k_bw_mb_s', 'N/A')} MB/s | {disk.get('randwrite_4k_lat_ms', 'N/A')} ms |",
        f"| **1M Sequential Read** | `{disk.get('seqread_1m_iops', 'N/A')}` IOPS | **{disk.get('seqread_1m_bw_mb_s', 'N/A')} MB/s** | - |",
        f"| **1M Sequential Write** | `{disk.get('seqwrite_1m_iops', 'N/A')}` IOPS | **{disk.get('seqwrite_1m_bw_mb_s', 'N/A')} MB/s** | - |",
        f"| **4K Mixed 70/30 (Total)** | `{disk.get('mixed_4k_total_iops', 'N/A')}` IOPS | (R: {disk.get('mixed_4k_read_iops', 'N/A')} / W: {disk.get('mixed_4k_write_iops', 'N/A')}) | - |",
        ""
    ]
    return "\n".join(lines)

def main():
    runner_label = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("RUNNER_LABEL", "local-runner")
    print(f"=== Starting Benchmarks for: {runner_label} ===")

    print("--> Collecting system info...")
    sys_info = get_sys_info()
    print(f"    Architecture: {sys_info['arch']}, CPU: {sys_info['cpu_model']}, Cores: {sys_info['cpu_cores']}, RAM: {sys_info['mem_total_gb']} GB")

    print("--> Running SHA256 benchmark...")
    sha_res = bench_sha256()
    print(f"    SHA256 Throughput: {sha_res['sha256_mb_per_sec']} MB/s")

    print("--> Running Sysbench CPU benchmark...")
    cpu_res = bench_sysbench_cpu()
    print(f"    Single-thread: {cpu_res.get('single_thread_eps')} eps, Multi-thread: {cpu_res.get('multi_thread_eps')} eps")

    print("--> Running Sysbench Memory benchmark...")
    mem_res = bench_sysbench_memory()
    print(f"    Read: {mem_res.get('mem_read_mib_sec')} MiB/s, Write: {mem_res.get('mem_write_mib_sec')} MiB/s")

    print("--> Running FIO Disk IOPS benchmark...")
    disk_res = bench_fio_disk()
    print(f"    4K Rand Read IOPS: {disk_res.get('randread_4k_iops')}, 4K Rand Write IOPS: {disk_res.get('randwrite_4k_iops')}")
    print(f"    1M Seq Read: {disk_res.get('seqread_1m_bw_mb_s')} MB/s, 1M Seq Write: {disk_res.get('seqwrite_1m_bw_mb_s')} MB/s")

    results_data = {
        "runner_label": runner_label,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "sys_info": sys_info,
        "sha256": sha_res,
        "cpu": cpu_res,
        "memory": mem_res,
        "disk": disk_res
    }

    results_dir = Path("results")
    results_dir.mkdir(exist_ok=True)
    out_file = results_dir / f"{runner_label}.json"
    with open(out_file, "w") as f:
        json.dump(results_data, f, indent=2)
    print(f"--> Saved results to {out_file}")

    # GitHub Step Summary
    summary_md = format_summary_markdown(runner_label, results_data)
    step_summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary_path:
        with open(step_summary_path, "a") as f:
            f.write(summary_md + "\n\n")
        print("--> Appended results to GITHUB_STEP_SUMMARY")
    else:
        print("\n=== Markdown Summary ===\n")
        print(summary_md)

if __name__ == "__main__":
    main()
