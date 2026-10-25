#!/usr/bin/env python3
"""
Hardware Virtualization & KVM Checker
Tests:
- /dev/kvm presence and user access
- KVM API functionality via ioctl (KVM_GET_API_VERSION)
- CPU Hardware Virtualization Extensions (Intel VMX, AMD SVM, ARM EL2)
- macOS Hypervisor.framework support (kern.hv_support)
"""

import os
import sys
import json
import time
import fcntl
import platform
import subprocess
from pathlib import Path

def run_cmd(cmd):
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        return res.stdout.strip()
    except Exception as e:
        return f"Error: {e}"

def check_kvm():
    system = platform.system()
    uname = platform.uname()
    arch = uname.machine

    report = {
        "system": system,
        "os_version": platform.platform(),
        "arch": arch,
        "kernel": uname.release,
        "cpu_model": "Unknown",
        "cpu_virt_extensions": False,
        "virt_tech": "None",
        "dev_kvm_exists": False,
        "dev_kvm_readable": False,
        "dev_kvm_writable": False,
        "kvm_api_functional": False,
        "kvm_api_version": None,
        "macos_hv_support": None,
        "summary_status": "UNSUPPORTED",
        "details": ""
    }

    if system == "Linux":
        # 1. CPU Model & Flags
        if os.path.exists("/proc/cpuinfo"):
            with open("/proc/cpuinfo", "r") as f:
                content = f.read()
                for line in content.splitlines():
                    if "model name" in line:
                        report["cpu_model"] = line.split(":", 1)[1].strip()
                        break
                    elif "Hardware" in line or "Processor" in line:
                        report["cpu_model"] = line.split(":", 1)[1].strip()

                if "vmx" in content:
                    report["cpu_virt_extensions"] = True
                    report["virt_tech"] = "Intel VT-x (vmx)"
                elif "svm" in content:
                    report["cpu_virt_extensions"] = True
                    report["virt_tech"] = "AMD-V (svm)"
                elif arch in ["aarch64", "arm64"]:
                    report["virt_tech"] = "ARMv8/v9 (EL2)"
                    # Check dmesg or cpuinfo
                    if "hyp" in content or "el2" in content.lower():
                        report["cpu_virt_extensions"] = True

        # 2. Check /dev/kvm
        if os.path.exists("/dev/kvm"):
            report["dev_kvm_exists"] = True
            report["dev_kvm_readable"] = os.access("/dev/kvm", os.R_OK)
            report["dev_kvm_writable"] = os.access("/dev/kvm", os.W_OK)

            # 3. Test KVM API ioctl
            KVM_GET_API_VERSION = 0xAE00
            try:
                fd = os.open("/dev/kvm", os.O_RDWR)
                ver = fcntl.ioctl(fd, KVM_GET_API_VERSION, 0)
                os.close(fd)
                report["kvm_api_functional"] = True
                report["kvm_api_version"] = ver
                report["summary_status"] = "FULL_KVM_ACCESS"
                report["details"] = f"KVM acceleration fully operational (API v{ver})"
            except PermissionError:
                report["summary_status"] = "KVM_PERMISSION_DENIED"
                report["details"] = "/dev/kvm exists but requires sudo or kvm group membership"
            except Exception as e:
                report["summary_status"] = "KVM_ERROR"
                report["details"] = f"Error opening /dev/kvm: {e}"
        else:
            report["summary_status"] = "NO_DEV_KVM"
            report["details"] = "/dev/kvm device node does not exist (nested virt disabled by host)"

    elif system == "Darwin":
        # macOS Virtualization check
        cpu_brand = run_cmd("sysctl -n machdep.cpu.brand_string")
        if cpu_brand and not cpu_brand.startswith("Error"):
            report["cpu_model"] = cpu_brand

        hv_support = run_cmd("sysctl -n kern.hv_support")
        if hv_support == "1":
            report["macos_hv_support"] = True
            report["cpu_virt_extensions"] = True
            report["virt_tech"] = "Apple Hypervisor.framework"
            report["summary_status"] = "HYPERVISOR_AVAILABLE"
            report["details"] = "Hypervisor.framework supported (hardware acceleration available)"
        elif hv_support == "0":
            report["macos_hv_support"] = False
            report["summary_status"] = "HYPERVISOR_DISABLED"
            report["details"] = "kern.hv_support=0 (virtualization disabled)"
        else:
            report["macos_hv_support"] = False
            report["summary_status"] = "NESTED_VIRT_UNAVAILABLE"
            report["details"] = f"Hypervisor.framework unavailable ({hv_support})"

    return report

def main():
    runner_label = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("RUNNER_LABEL", "local-test")
    print(f"=== Checking KVM / Virtualization for: {runner_label} ===")

    report = check_kvm()
    report["runner_label"] = runner_label
    report["timestamp"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    print(f"OS: {report['system']} ({report['arch']})")
    print(f"CPU: {report['cpu_model']}")
    print(f"Hardware Virt Tech: {report['virt_tech']}")
    print(f"Status: {report['summary_status']} - {report['details']}")

    results_dir = Path("results")
    results_dir.mkdir(exist_ok=True)
    out_file = results_dir / f"kvm-{runner_label}.json"
    with open(out_file, "w") as f:
        json.dump(report, f, indent=2)

    # Markdown Summary
    md_lines = [
        f"### 🖥️ KVM & Virtualization Status: `{runner_label}`",
        f"- **OS / Arch**: `{report['system']} ({report['arch']})`",
        f"- **CPU Model**: `{report['cpu_model']}`",
        f"- **Hardware Virt Extensions**: `{'✅ ' + report['virt_tech'] if report['cpu_virt_extensions'] else '❌ None'}`",
        f"- **`/dev/kvm` Available**: `{'✅ Yes' if report['dev_kvm_exists'] else '❌ No'}`",
        f"- **Functional KVM / Hypervisor**: `{'✅ Functional' if (report['kvm_api_functional'] or report['macos_hv_support']) else '❌ Unsupported'}`",
        f"- **Status**: **`{report['summary_status']}`** ({report['details']})",
        ""
    ]
    summary_md = "\n".join(md_lines)

    step_summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary_path:
        with open(step_summary_path, "a") as f:
            f.write(summary_md + "\n")
    else:
        print("\n" + summary_md)

if __name__ == "__main__":
    main()
