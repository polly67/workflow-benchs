#!/usr/bin/env python3
"""
Aggregate and compare all benchmark JSON files in results/
Produces a side-by-side Markdown comparison table.
"""

import os
import glob
import json
from pathlib import Path

def generate_comparison_table():
    results_dir = Path("results")
    json_files = sorted(list(results_dir.glob("*.json")))

    if not json_files:
        print("No benchmark JSON files found in results/")
        return ""

    runs = []
    for jf in json_files:
        try:
            with open(jf, "r") as f:
                runs.append(json.load(f))
        except Exception as e:
            print(f"Error reading {jf}: {e}")

    if not runs:
        return ""

    # Sort runs in a clean, logical order
    preferred_order = ["ubuntu-latest", "ubuntu-24.04-arm", "macos-latest", "macos-15-intel", "self-hosted"]
    runs.sort(key=lambda r: preferred_order.index(r.get("runner_label")) if r.get("runner_label") in preferred_order else 99)

    runners = [r.get("runner_label", "unknown") for r in runs]

    header_cols = ["Metric"] + [f"`{r}`" for r in runners]
    separator_cols = [":---"] + [":---:" for _ in runners]

    rows = []

    def add_row(metric_name, getter_fn):
        row = [metric_name]
        for r in runs:
            val = getter_fn(r)
            row.append(str(val) if val is not None else "N/A")
        rows.append(row)

    def section_header(title):
        rows.append([f"**{title}**"] + ["" for _ in runners])

    # System specs
    section_header("🖥️ System Specs")
    add_row("Architecture", lambda r: r["sys_info"].get("arch"))
    add_row("OS Version", lambda r: r["sys_info"].get("os_name"))
    add_row("Kernel", lambda r: r["sys_info"].get("kernel"))
    add_row("CPU Model", lambda r: r["sys_info"].get("cpu_model"))
    add_row("vCPUs", lambda r: r["sys_info"].get("cpu_cores"))
    add_row("RAM Total (GB)", lambda r: r["sys_info"].get("mem_total_gb"))
    add_row("Disk Total (GB)", lambda r: r["sys_info"].get("disk_total_gb"))
    add_row("Disk Free (GB)", lambda r: r["sys_info"].get("disk_free_gb"))

    # CPU Compute
    section_header("🧠 CPU Performance")
    add_row("Sysbench Single-Thread (events/s)", lambda r: f"**{r.get('cpu', {}).get('single_thread_eps', 'N/A')}**")
    add_row("Sysbench Single-Thread Avg Latency (ms)", lambda r: r.get("cpu", {}).get("single_thread_lat_avg_ms", "N/A"))
    add_row("Sysbench Multi-Thread (events/s)", lambda r: f"**{r.get('cpu', {}).get('multi_thread_eps', 'N/A')}**")
    add_row("Sysbench Multi-Thread Avg Latency (ms)", lambda r: r.get("cpu", {}).get("multi_thread_lat_avg_ms", "N/A"))
    add_row("SHA256 Throughput (MB/s)", lambda r: f"**{r.get('sha256', {}).get('sha256_mb_per_sec', 'N/A')}**")

    # Memory
    section_header("💾 Memory Bandwidth")
    add_row("Sysbench Mem Read (MiB/s)", lambda r: f"**{r.get('memory', {}).get('mem_read_mib_sec', 'N/A')}**")
    add_row("Sysbench Mem Write (MiB/s)", lambda r: f"**{r.get('memory', {}).get('mem_write_mib_sec', 'N/A')}**")

    # Disk IOPS & Bandwidth
    section_header("🚀 Disk IOPS & Throughput (fio)")
    add_row("4K Random Read IOPS", lambda r: f"**{r.get('disk', {}).get('randread_4k_iops', 'N/A')}**")
    add_row("4K Random Read Latency (ms)", lambda r: r.get("disk", {}).get("randread_4k_lat_ms", "N/A"))
    add_row("4K Random Read Bandwidth (MB/s)", lambda r: r.get("disk", {}).get("randread_4k_bw_mb_s", "N/A"))
    add_row("4K Random Write IOPS", lambda r: f"**{r.get('disk', {}).get('randwrite_4k_iops', 'N/A')}**")
    add_row("4K Random Write Latency (ms)", lambda r: r.get("disk", {}).get("randwrite_4k_lat_ms", "N/A"))
    add_row("4K Random Write Bandwidth (MB/s)", lambda r: r.get("disk", {}).get("randwrite_4k_bw_mb_s", "N/A"))
    add_row("1M Sequential Read (MB/s)", lambda r: f"**{r.get('disk', {}).get('seqread_1m_bw_mb_s', 'N/A')}**")
    add_row("1M Sequential Write (MB/s)", lambda r: f"**{r.get('disk', {}).get('seqwrite_1m_bw_mb_s', 'N/A')}**")
    add_row("4K Mixed 70/30 Total IOPS", lambda r: f"**{r.get('disk', {}).get('mixed_4k_total_iops', 'N/A')}**")

    md_lines = [
        "# 📊 GitHub Actions Free Runners Benchmark Comparison",
        "",
        "Comparison of GitHub Actions standard hosted runners for public repositories (x86-64 vs ARM64).",
        "",
        "| " + " | ".join(header_cols) + " |",
        "| " + " | ".join(separator_cols) + " |",
    ]

    for row in rows:
        md_lines.append("| " + " | ".join(row) + " |")

    md_lines.append("")
    return "\n".join(md_lines)

def update_readme(table_md):
    readme_path = Path("README.md")
    if not readme_path.exists():
        return

    content = readme_path.read_text()
    marker_start = "<!-- BENCHMARK_RESULTS_START -->"
    marker_end = "<!-- BENCHMARK_RESULTS_END -->"

    replacement = f"{marker_start}\n\n{table_md}\n\n{marker_end}"

    if marker_start in content and marker_end in content:
        parts = content.split(marker_start)
        tail = parts[1].split(marker_end)[1]
        new_content = parts[0] + replacement + tail
    else:
        new_content = content + f"\n\n## 📊 Latest Benchmark Results\n\n{replacement}\n"

    readme_path.write_text(new_content)
    print("--> Updated README.md with benchmark results")

def main():
    table_md = generate_comparison_table()
    if not table_md:
        print("No comparison table generated.")
        return

    summary_file = Path("results/SUMMARY.md")
    summary_file.parent.mkdir(exist_ok=True)
    summary_file.write_text(table_md)
    print(f"--> Saved comparison to {summary_file}")

    update_readme(table_md)

    step_summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary_path:
        with open(step_summary_path, "a") as f:
            f.write("\n\n" + table_md + "\n\n")
        print("--> Appended comparison table to GITHUB_STEP_SUMMARY")

if __name__ == "__main__":
    main()
