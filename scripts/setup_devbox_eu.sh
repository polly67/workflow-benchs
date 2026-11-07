#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOMEBREW_NO_INSTALL_CLEANUP=1

SUN_USER="${SUN_USER:-runner}"
SUN_PASS="${SUN_PASS:-root}"
DISP_W="${DISP_W:-1280}"
DISP_H="${DISP_H:-720}"
TS_AUTHKEY="${TS_AUTHKEY:?TS_AUTHKEY is required}"
LOCAL_USER="$(id -un)"
LOCAL_UID="$(id -u)"

echo "=== [1/6] Installing Tailscale, BetterDisplay, DisplayPlacer, Sunshine & AsyncSSH ==="
brew update --quiet
export HOMEBREW_NO_AUTO_UPDATE=1

brew install tailscale
brew install --cask betterdisplay || true
rm -f /opt/homebrew/bin/betterdisplaycli
brew install waydabber/betterdisplay/betterdisplaycli displayplacer
brew link --overwrite betterdisplaycli || true
brew install lizardbyte/homebrew/sunshine

python3 -m venv "$HOME/.ssh-venv"
"$HOME/.ssh-venv/bin/pip" install --upgrade pip asyncssh --quiet

echo "=== [2/6] Optimizing macOS Sequoia & Disabling Sleep ==="
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false || true
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001 || true
defaults write com.apple.universalaccess reduceTransparency -bool true || true
defaults write com.apple.universalaccess reduceMotion -bool true || true
defaults write com.apple.dock expose-animation-duration -float 0.05 || true
defaults write com.apple.dock launchanim -bool false || true
defaults write com.apple.dock autohide-time-modifier -float 0.05 || true
sudo mdutil -a -i off 2>/dev/null || true
sudo softwareupdate --schedule off 2>/dev/null || true
sudo pmset -a sleep 0 displaysleep 0 disksleep 0 2>/dev/null || true
killall Dock 2>/dev/null || true

# Keep system awake via LaunchDaemon
cat << 'EOF' | sudo tee /Library/LaunchDaemons/com.stream.caffeinate.plist >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.stream.caffeinate</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/caffeinate</string>
    <string>-d</string><string>-i</string><string>-m</string><string>-s</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
EOF
sudo launchctl bootout system/com.stream.caffeinate 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/com.stream.caffeinate.plist

echo "=== [3/6] Starting Tailscale Daemon & Connecting to Tailnet ==="
sudo brew services start tailscale || true
for i in {1..20}; do
  if sudo tailscale status >/dev/null 2>&1 || [ -S /var/run/tailscaled.socket ]; then
    break
  fi
  sleep 1
done

sudo tailscale up --authkey="$TS_AUTHKEY" --hostname="mac-eu-zurich" --accept-dns=false
sleep 2

# Ensure public DNS stays active alongside MagicDNS
networksetup -listallnetworkservices | tail -n +2 | sed 's/^\*//' | while IFS= read -r svc; do
  if [ -n "$svc" ]; then
    sudo networksetup -setdnsservers "$svc" 1.1.1.1 8.8.8.8 100.100.100.100 2>/dev/null || true
  fi
done
sudo dscacheutil -flushcache 2>/dev/null || true
sudo killall -HUP mDNSResponder 2>/dev/null || true

TS_IP="$(tailscale ip -4 | head -n1 | tr -d '[:space:]')"
TS_IPV6="$(tailscale ip -6 2>/dev/null | head -n1 | tr -d '[:space:]' || true)"
TS_JSON="$(tailscale status --json)"
TS_FQDN="$(python3 -c 'import sys,json; d=json.loads(sys.argv[1]); print(d.get("Self",{}).get("DNSName","").rstrip("."))' "$TS_JSON")"
TS_HOST="$(python3 -c 'import sys,json; d=json.loads(sys.argv[1]); print(d.get("Self",{}).get("HostName",""))' "$TS_JSON")"
echo "Connected Tailscale IPv4: $TS_IP ($TS_FQDN)"

echo "=== [4/6] Starting BetterDisplay LaunchAgent & Creating 1:1 Non-HiDPI Virtual Screen ==="
mkdir -p "$HOME/Library/LaunchAgents"
cat << 'EOF' > "$HOME/Library/LaunchAgents/com.stream.betterdisplay.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.stream.betterdisplay</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/betterdisplay.log</string>
  <key>StandardErrorPath</key><string>/tmp/betterdisplay.log</string>
</dict>
</plist>
EOF
launchctl bootout "gui/${LOCAL_UID}/com.stream.betterdisplay" 2>/dev/null || true
launchctl bootstrap "gui/${LOCAL_UID}" "$HOME/Library/LaunchAgents/com.stream.betterdisplay.plist"
sleep 5

betterdisplaycli create -deviceType=virtualScreen -virtualScreenName="StreamDisplay" -aspectWidth=16 -aspectHeight=9 -virtualScreenHiDPI=off || true
sleep 3
betterdisplaycli set -name="StreamDisplay" -connected=on || true
betterdisplaycli set -name="StreamDisplay" -virtualScreenHiDPI=off || true
sleep 2

python3 - "$DISP_W" "$DISP_H" << 'PYEOF'
import ctypes, json, re, subprocess, sys

target_w, target_h = sys.argv[1], sys.argv[2]
stream_cg_id = "2"
apple_cg_id = "1"
try:
    raw_ident = subprocess.check_output(["/opt/homebrew/bin/betterdisplaycli", "get", "-identifiers"], text=True, stderr=subprocess.DEVNULL)
    items = json.loads("[" + raw_ident.strip().strip(",") + "]")
    for it in items:
        if it.get("name") == "StreamDisplay" and it.get("displayID"):
            stream_cg_id = str(it["displayID"])
        elif "Apple Virtual" in it.get("name", "") and it.get("displayID"):
            apple_cg_id = str(it["displayID"])
except Exception as e:
    print("Warning parsing betterdisplaycli identifiers:", e)

with open("/Users/runner/.stream_display_id", "w") as f:
    f.write(stream_cg_id)

dp_out = subprocess.run(["/opt/homebrew/bin/displayplacer", "list"], capture_output=True, text=True).stdout
blocks = dp_out.split("Persistent screen id:")
ctx_to_pers = {}
for b in blocks[1:]:
    lines = b.strip().splitlines()
    pers_id = lines[0].strip()
    m = re.search(r"Contextual screen id:\s*(\d+)", b)
    if m:
        ctx_to_pers[m.group(1)] = pers_id

s_id = ctx_to_pers.get(stream_cg_id, stream_cg_id)
a_id = ctx_to_pers.get(apple_cg_id, apple_cg_id)
with open("/Users/runner/.stream_dp_ids", "w") as f:
    f.write(f"{s_id}\n{a_id}\n")

cmds = [
    ["/opt/homebrew/bin/displayplacer", f"id:{s_id}+{a_id} res:{target_w}x{target_h} scaling:off origin:(0,0) degree:0"],
    ["/opt/homebrew/bin/displayplacer", f"id:{s_id} res:{target_w}x{target_h} scaling:off origin:(0,0) degree:0"],
    ["/opt/homebrew/bin/displayplacer", f"id:{s_id} res:{target_w}x{target_h} origin:(0,0) degree:0"],
]
for cmd in cmds:
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode == 0:
        break

cg = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
cg.CGDisplayPixelsWide.argtypes = [ctypes.c_uint32]
cg.CGDisplayPixelsWide.restype = ctypes.c_size_t
cg.CGDisplayPixelsHigh.argtypes = [ctypes.c_uint32]
cg.CGDisplayPixelsHigh.restype = ctypes.c_size_t
did = int(stream_cg_id)
actual = f"{cg.CGDisplayPixelsWide(did)}x{cg.CGDisplayPixelsHigh(did)}"
print(f"Verified StreamDisplay (CGDirectDisplayID={stream_cg_id}) framebuffer: {actual}")
PYEOF

sudo mkdir -p /usr/local/bin
cat << 'EOF' | sudo tee /usr/local/bin/set-res >/dev/null
#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
RES="${1:-1280x720}"
SID=$(sed -n '1p' /Users/runner/.stream_dp_ids 2>/dev/null || echo "3")
AID=$(sed -n '2p' /Users/runner/.stream_dp_ids 2>/dev/null || echo "1")
displayplacer "id:${SID}+${AID} res:${RES} scaling:off origin:(0,0) degree:0" || \
displayplacer "id:${SID} res:${RES} scaling:off origin:(0,0) degree:0"
echo "Updated display resolution to $RES (scaling:off)"
EOF
sudo chmod +x /usr/local/bin/set-res
cp /usr/local/bin/set-res /opt/homebrew/bin/set-res 2>/dev/null || true

echo "=== [5/6] Configuring & Starting Persistent AsyncSSH Server on ${TS_IP}:22 ==="
cat << EOF | sudo tee /Library/LaunchDaemons/com.stream.asyncssh.plist >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.stream.asyncssh</string>
  <key>ProgramArguments</key>
  <array>
    <string>${HOME}/.ssh-venv/bin/python</string>
    <string>${HOME}/ssh_server.py</string>
    <string>--host</string><string>127.0.0.1,${TS_IP}</string>
    <string>--port</string><string>22</string>
    <string>--user</string><string>${SUN_USER}</string>
    <string>--password</string><string>${SUN_PASS}</string>
    <string>--run-as</string><string>${LOCAL_USER}</string>
    <string>--host-key</string><string>${HOME}/.ssh_host_ed25519</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/asyncssh.log</string>
  <key>StandardErrorPath</key><string>/tmp/asyncssh.log</string>
</dict>
</plist>
EOF
sudo launchctl bootout system/com.stream.asyncssh 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/com.stream.asyncssh.plist
sleep 2

python3 - "$SUN_USER" "$SUN_PASS" "$TS_IP" << 'PYEOF'
import os, pty, select, sys, time
user, pw, host = sys.argv[1], sys.argv[2], sys.argv[3]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("ssh", [
        "ssh", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
        "-o", "PreferredAuthentications=password,keyboard-interactive",
        "-o", "PubkeyAuthentication=no", f"{user}@{host}", "id -un && echo SSH_TAILSCALE_OK"
    ])
buf = b""
sent = False
deadline = time.time() + 15
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.5)
    if r:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        if (b"assword:" in buf or b"Password:" in buf) and not sent:
            os.write(fd, (pw + "\n").encode())
            sent = True
        if b"SSH_TAILSCALE_OK" in buf:
            print("Verified SSH login on Tailscale IP:", host)
            sys.exit(0)
print("SSH test failed:", buf.decode(errors="replace"))
sys.exit(1)
PYEOF

echo "=== [6/6] Configuring Sunshine & Creating run_sunshine.sh Wrapper ==="
mkdir -p "$HOME/.config/sunshine"
STREAM_CG_ID="$(cat /Users/runner/.stream_display_id 2>/dev/null || echo "3")"
ORIGINS="$(python3 - "$TS_IP" "$TS_IPV6" "$TS_FQDN" "$TS_HOST" << 'PYEOF'
import sys
ip4, ip6, fqdn, host = sys.argv[1:5]
hosts = []
for h in [ip4, f"[{ip6}]" if ip6 else "", fqdn, fqdn.lower(), host, host.lower(), "localhost", "127.0.0.1"]:
    if h and h not in hosts:
        hosts.append(h)
origins = []
for h in hosts:
    origins.append(f"https://{h}:47990")
    origins.append(f"https://{h}")
print(",".join(origins))
PYEOF
)"

cat << EOF > "$HOME/.config/sunshine/sunshine.conf"
sunshine_name = macOS-Zurich-EU
address_family = both
origin_web_ui_allowed = wan
csrf_allowed_origins = $ORIGINS
output_name = $STREAM_CG_ID
encoder = videotoolbox
vt_coder = cavlc
vt_realtime = enabled
vt_software = disabled
fec_percentage = 5
qp = 26
min_threads = 2
EOF

/opt/homebrew/bin/sunshine "$HOME/.config/sunshine/sunshine.conf" --creds "$SUN_USER" "$SUN_PASS"

cat << 'EOF' > "$HOME/run_sunshine.sh"
#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

pgrep -x BetterDisplay >/dev/null 2>&1 || (/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay >/tmp/betterdisplay.log 2>&1 </dev/null &)
for i in {1..10}; do
  if /opt/homebrew/bin/betterdisplaycli get -identifiers 2>/dev/null | grep -q "StreamDisplay"; then
    break
  fi
  sleep 1
done
/opt/homebrew/bin/betterdisplaycli set -name="StreamDisplay" -connected=on >/dev/null 2>&1 || true
/usr/local/bin/set-res 1280x720 >/dev/null 2>&1 || true

exec /opt/homebrew/bin/sunshine "$HOME/.config/sunshine/sunshine.conf"
EOF
chmod +x "$HOME/run_sunshine.sh"

echo "=========================================================="
echo "ZURICH SWITZERLAND DEVBOX CONFIGURED!"
echo "Next: Register Sunshine under Devbox's pre-authorized agent:"
echo "  setsid devbox service create mac-eu --name sunshine --cwd /Users/runner --no_logs -- /Users/runner/run_sunshine.sh </dev/null"
echo "Tailscale IP:    $TS_IP ($TS_FQDN)"
echo "Sunshine Web UI: https://${TS_IP}:47990"
echo "SSH Command:     ssh ${SUN_USER}@${TS_IP} (password: ${SUN_PASS})"
echo "=========================================================="
