#!/usr/bin/env python3
"""
Aggregate and compare all KVM check reports in results/kvm-*.json
"""

import os
import json
from pathlib import Path

def generate_kvm_table():
    results_dir = Path("results")
    json_files = sorted(list(results_dir.glob("kvm-*.json")))

    if not json_files:
        print("No kvm-*.json files found.")
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

    preferred_order = ["ubuntu-latest", "ubuntu-24.04-arm", "macos-latest", "macos-15-intel", "self-hosted"]
    runs.sort(key=lambda r: preferred_order.index(r.get("runner_label")) if r.get("runner_label") in preferred_order else 99)

    runners = [r.get("runner_label", "unknown") for r in runs]

    header_cols = ["Feature / Check"] + [f"`{r}`" for r in runners]
    separator_cols = [":---"] + [":---:" for _ in runners]

    rows = []

    def add_row(metric_name, getter_fn):
        row = [metric_name]
        for r in runs:
            val = getter_fn(r)
            row.append(str(val) if val is not None else "N/A")
        rows.append(row)

    add_row("OS & Architecture", lambda r: f"{r.get('system')} ({r.get('arch')})")
    add_row("CPU Model", lambda r: r.get("cpu_model"))
    add_row("Virtualization Tech", lambda r: f"**{r.get('virt_tech')}**" if r.get("cpu_virt_extensions") else "None")
    add_row("`/dev/kvm` Present?", lambda r: "✅ Yes" if r.get("dev_kvm_exists") else "❌ No")
    add_row("`/dev/kvm` Read/Write?", lambda r: "✅ Yes" if (r.get("dev_kvm_readable") and r.get("dev_kvm_writable")) else ("⚠️ Sudo only" if r.get("dev_kvm_exists") else "❌ No"))
    add_row("KVM ioctl Functional?", lambda r: f"✅ API v{r.get('kvm_api_version')}" if r.get("kvm_api_functional") else ("N/A (macOS)" if r.get("system") == "Darwin" else "❌ No"))
    add_row("Hardware Acceleration?", lambda r: "**✅ FULL ACCESS**" if (r.get("kvm_api_functional") or r.get("macos_hv_support")) else "**❌ DISABLED**")
    add_row("Verdict / Details", lambda r: r.get("details"))

    md_lines = [
        "# 🛡️ KVM & Hardware Virtualization Support Matrix",
        "",
        "Testing `/dev/kvm`, nested virtualization, and Hypervisor.framework across all runners.",
        "",
        "| " + " | ".join(header_cols) + " |",
        "| " + " | ".join(separator_cols) + " |"
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
    marker_start = "<!-- KVM_RESULTS_START -->"
    marker_end = "<!-- KVM_RESULTS_END -->"

    replacement = f"{marker_start}\n\n{table_md}\n\n{marker_end}"

    if marker_start in content and marker_end in content:
        parts = content.split(marker_start)
        tail = parts[1].split(marker_end)[1]
        new_content = parts[0] + replacement + tail
    else:
        new_content = content + f"\n\n## 🛡️ KVM & Virtualization Access\n\n{replacement}\n"

    readme_path.write_text(new_content)
    print("--> Updated README.md with KVM results")

def main():
    table_md = generate_kvm_table()
    if not table_md:
        print("No KVM comparison table generated.")
        return

    summary_file = Path("results/KVM_SUMMARY.md")
    summary_file.parent.mkdir(exist_ok=True)
    summary_file.write_text(table_md)
    print(f"--> Saved KVM summary to {summary_file}")

    update_readme(table_md)

    step_summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary_path:
        with open(step_summary_path, "a") as f:
            f.write("\n\n" + table_md + "\n\n")

if __name__ == "__main__":
    main()
