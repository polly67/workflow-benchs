#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Persistent macOS Sequoia Streamer Setup & Restore Script (/Volumes/devbox)
# Restores Roblox + all login/game data, Prism Launcher, Tailscale, BetterDisplay
# (1280x720 1:1 non-HiDPI), AsyncSSH (runner/root), and Sunshine + Moonlight pairing.
# Safe to run anytime (both automatically on fresh boot and manually via SSH/CLI).
# ==============================================================================

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

PERSIST_DIR="/Volumes/devbox/persist"
WORKSPACE_DIR="/Volumes/devbox/workspace"
export HOMEBREW_CACHE="$PERSIST_DIR/brew-cache"

SUN_USER="${SUN_USER:-runner}"
SUN_PASS="${SUN_PASS:-root}"
DISP_W="${DISP_W:-1280}"
DISP_H="${DISP_H:-720}"
TS_AUTHKEY="${TS_AUTHKEY:-$(cat "$PERSIST_DIR/.ts_authkey" 2>/dev/null || true)}"
LOCAL_USER="$(id -un)"
LOCAL_UID="$(id -u)"

mkdir -p "$PERSIST_DIR" "$HOMEBREW_CACHE"

# Prevent 15-minute Devbox idle auto-stop while streaming over Moonlight/Tailscale
if [ -n "${NAMESPACE_DEVBOX_TASKS_DIR:-}" ] && [ -d "${NAMESPACE_DEVBOX_TASKS_DIR}" ]; then
  touch "${NAMESPACE_DEVBOX_TASKS_DIR}/moonlight-stream" 2>/dev/null || true
elif [ -d "/var/run/devbox/tasks" ]; then
  touch "/var/run/devbox/tasks/moonlight-stream" 2>/dev/null || true
fi

touch /tmp/.persist_restore_in_progress
trap 'rm -f /tmp/.persist_restore_in_progress' EXIT

echo "=== [1/7] Restoring Roblox, Prism Launcher & User Data from Persistent Storage ==="
if [ -d "$PERSIST_DIR/Applications/Roblox.app" ] && [ ! -d "/Applications/Roblox.app" ]; then
  echo "  -> Restoring /Applications/Roblox.app..."
  rsync -a "$PERSIST_DIR/Applications/Roblox.app/" "/Applications/Roblox.app/"
fi
if [ -d "$PERSIST_DIR/Applications/Prism Launcher.app" ] && [ ! -d "/Applications/Prism Launcher.app" ]; then
  echo "  -> Restoring /Applications/Prism Launcher.app..."
  rsync -a "$PERSIST_DIR/Applications/Prism Launcher.app/" "/Applications/Prism Launcher.app/"
fi
if [ -d "$PERSIST_DIR/Applications/BetterDisplay.app" ] && [ ! -d "/Applications/BetterDisplay.app" ]; then
  echo "  -> Restoring /Applications/BetterDisplay.app..."
  rsync -a "$PERSIST_DIR/Applications/BetterDisplay.app/" "/Applications/BetterDisplay.app/"
fi

# Restore Roblox login session, Keychain, cookies, WebKit & caches (only if Roblox isn't actively open)
if ! pgrep -x RobloxPlayer >/dev/null 2>&1; then
  mkdir -p "$HOME/Library/Preferences" "$HOME/Library/HTTPStorages" "$HOME/Library/WebKit" "$HOME/Library/Caches" "$HOME/Library/Application Support"
  [ -d "$PERSIST_DIR/roblox-data/Library-Roblox" ] && rsync -a "$PERSIST_DIR/roblox-data/Library-Roblox/" "$HOME/Library/Roblox/"
  [ -d "$PERSIST_DIR/roblox-data/WebKit-RobloxPlayer" ] && rsync -a "$PERSIST_DIR/roblox-data/WebKit-RobloxPlayer/" "$HOME/Library/WebKit/com.roblox.RobloxPlayer/"
  [ -d "$PERSIST_DIR/roblox-data/Caches-RobloxPlayer" ] && rsync -a "$PERSIST_DIR/roblox-data/Caches-RobloxPlayer/" "$HOME/Library/Caches/com.roblox.RobloxPlayer/"
  [ -d "$PERSIST_DIR/roblox-data/HTTPStorages/com.roblox.RobloxPlayer" ] && rsync -a "$PERSIST_DIR/roblox-data/HTTPStorages/com.roblox.RobloxPlayer/" "$HOME/Library/HTTPStorages/com.roblox.RobloxPlayer/"
  [ -f "$PERSIST_DIR/roblox-data/HTTPStorages/com.roblox.RobloxPlayer.binarycookies" ] && cp -p "$PERSIST_DIR/roblox-data/HTTPStorages/com.roblox.RobloxPlayer.binarycookies" "$HOME/Library/HTTPStorages/"
  for pf in "$PERSIST_DIR/roblox-data/Preferences"/com.roblox.*.plist; do
    [ -f "$pf" ] && cp -p "$pf" "$HOME/Library/Preferences/"
  done
  if [ -f "$PERSIST_DIR/roblox-data/Keychains/login.keychain-db" ]; then
    mkdir -p "$HOME/Library/Keychains"
    cp -p "$PERSIST_DIR/roblox-data/Keychains/login.keychain-db" "$HOME/Library/Keychains/login.keychain-db"
  fi
  # Restore Prism Launcher data
  [ -d "$PERSIST_DIR/prism-data/PrismLauncher" ] && rsync -a "$PERSIST_DIR/prism-data/PrismLauncher/" "$HOME/Library/Application Support/PrismLauncher/"
  for pf in "$PERSIST_DIR/prism-data/Preferences"/org.prismlauncher.*.plist; do
    [ -f "$pf" ] && cp -p "$pf" "$HOME/Library/Preferences/"
  done
  killall cfprefsd 2>/dev/null || true
fi

echo "=== [2/7] Ensuring Homebrew Packages & Python AsyncSSH Are Installed ==="
if [ -d "$PERSIST_DIR/brew-taps" ]; then
  mkdir -p /opt/homebrew/Library/Taps
  rsync -a --ignore-existing "$PERSIST_DIR/brew-taps/" /opt/homebrew/Library/Taps/ 2>/dev/null || true
fi

command -v tailscale >/dev/null 2>&1 || brew install tailscale
[ -d "/Applications/BetterDisplay.app" ] || brew install --cask betterdisplay || true
if ! command -v betterdisplaycli >/dev/null 2>&1 || ! command -v displayplacer >/dev/null 2>&1; then
  rm -f /opt/homebrew/bin/betterdisplaycli
  brew install waydabber/betterdisplay/betterdisplaycli displayplacer
  brew link --overwrite betterdisplaycli || true
fi
command -v sunshine >/dev/null 2>&1 || brew install lizardbyte/homebrew/sunshine
if [ -x "$PERSIST_DIR/bin/sunshine" ]; then
  for sb in /opt/homebrew/Cellar/sunshine/*/bin/sunshine; do
    [ -f "$sb" ] && cp -f "$PERSIST_DIR/bin/sunshine" "$sb" && chmod +x "$sb"
  done
fi

if [ ! -x "$HOME/.ssh-venv/bin/python" ]; then
  python3 -m venv "$HOME/.ssh-venv"
  if [ -d "$PERSIST_DIR/pip-wheels" ] && ls "$PERSIST_DIR/pip-wheels"/*.whl >/dev/null 2>&1; then
    "$HOME/.ssh-venv/bin/pip" install --no-index --find-links="$PERSIST_DIR/pip-wheels" asyncssh --quiet
  else
    "$HOME/.ssh-venv/bin/pip" install --upgrade pip asyncssh --quiet
  fi
fi

echo "=== [3/7] Applying macOS Sequoia Low-Latency & No-Sleep Settings ==="
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false || true
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001 || true
defaults write com.apple.universalaccess reduceTransparency -bool true || true
defaults write com.apple.universalaccess reduceMotion -bool true || true
sudo mdutil -a -i off 2>/dev/null || true
sudo softwareupdate --schedule off 2>/dev/null || true
sudo pmset -a sleep 0 displaysleep 0 disksleep 0 2>/dev/null || true

if [ ! -f /Library/LaunchDaemons/com.stream.caffeinate.plist ]; then
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
  sudo launchctl bootstrap system /Library/LaunchDaemons/com.stream.caffeinate.plist 2>/dev/null || true
fi

echo "=== [4/7] Connecting Tailscale (Restoring Persistent IP if Saved) ==="
if ! pgrep -x tailscaled >/dev/null 2>&1; then
  if [ -f "$PERSIST_DIR/tailscale/tailscaled.state" ] && ! sudo test -f /Library/Tailscale/tailscaled.state; then
    sudo mkdir -p /Library/Tailscale
    sudo cp -p "$PERSIST_DIR/tailscale/tailscaled.state" /Library/Tailscale/tailscaled.state
    sudo chmod 600 /Library/Tailscale/tailscaled.state
  fi
  sudo brew services start tailscale >/dev/null 2>&1 || true
  for i in {1..20}; do
    if sudo tailscale status >/dev/null 2>&1 || [ -S /var/run/tailscaled.socket ]; then
      break
    fi
    sleep 1
  done
fi

if ! tailscale ip -4 >/dev/null 2>&1 || [ -z "$(tailscale ip -4 2>/dev/null | tr -d '[:space:]')" ]; then
  sudo tailscale up --authkey="$TS_AUTHKEY" --hostname="mac-eu-zurich" --accept-dns=false
  sleep 2
else
  sudo tailscale set --accept-dns=false 2>/dev/null || true
fi

networksetup -listallnetworkservices | tail -n +2 | sed 's/^\*//' | while IFS= read -r svc; do
  if [ -n "$svc" ]; then
    sudo networksetup -setdnsservers "$svc" 1.1.1.1 8.8.8.8 100.100.100.100 2>/dev/null || true
  fi
done

TS_IP="$(tailscale ip -4 | head -n1 | tr -d '[:space:]')"
TS_IPV6="$(tailscale ip -6 2>/dev/null | head -n1 | tr -d '[:space:]' || true)"
TS_JSON="$(tailscale status --json)"
TS_FQDN="$(python3 -c 'import sys,json; d=json.loads(sys.argv[1]); print(d.get("Self",{}).get("DNSName","").rstrip("."))' "$TS_JSON")"
TS_HOST="$(python3 -c 'import sys,json; d=json.loads(sys.argv[1]); print(d.get("Self",{}).get("HostName",""))' "$TS_JSON")"
echo "  -> Tailscale Live IP: $TS_IP ($TS_FQDN)"

echo "=== [5/7] Ensuring BetterDisplay 1:1 Virtual Screen (${DISP_W}x${DISP_H}) ==="
if ! pgrep -x BetterDisplay >/dev/null 2>&1; then
  [ -f "$PERSIST_DIR/betterdisplay/pro.betterdisplay.BetterDisplay.plist" ] && cp -p "$PERSIST_DIR/betterdisplay/pro.betterdisplay.BetterDisplay.plist" "$HOME/Library/Preferences/" 2>/dev/null || true
  [ -d "$PERSIST_DIR/betterdisplay/AppSupport" ] && rsync -a "$PERSIST_DIR/betterdisplay/AppSupport/" "$HOME/Library/Application Support/BetterDisplay/" 2>/dev/null || true
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
  sleep 4
fi

if ! betterdisplaycli get -identifiers 2>/dev/null | grep -q "StreamDisplay"; then
  betterdisplaycli create -deviceType=virtualScreen -virtualScreenName="StreamDisplay" -aspectWidth=16 -aspectHeight=9 -virtualScreenHiDPI=off || true
  sleep 2
fi
betterdisplaycli set -name="StreamDisplay" -connected=on >/dev/null 2>&1 || true
betterdisplaycli set -name="StreamDisplay" -virtualScreenHiDPI=off >/dev/null 2>&1 || true

python3 - "$DISP_W" "$DISP_H" << 'PYEOF'
import ctypes, json, re, subprocess, sys
target_w, target_h = sys.argv[1], sys.argv[2]
stream_cg_id, apple_cg_id = "3", "1"
try:
    raw_ident = subprocess.check_output(["/opt/homebrew/bin/betterdisplaycli", "get", "-identifiers"], text=True, stderr=subprocess.DEVNULL)
    items = json.loads("[" + raw_ident.strip().strip(",") + "]")
    for it in items:
        if it.get("name") == "StreamDisplay" and it.get("displayID"):
            stream_cg_id = str(it["displayID"])
        elif "Apple Virtual" in it.get("name", "") and it.get("displayID"):
            apple_cg_id = str(it["displayID"])
except Exception:
    pass
with open("/Users/runner/.stream_display_id", "w") as f:
    f.write(stream_cg_id)

cg = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
cg.CGDisplayPixelsWide.argtypes = [ctypes.c_uint32]
cg.CGDisplayPixelsWide.restype = ctypes.c_size_t
cg.CGDisplayPixelsHigh.argtypes = [ctypes.c_uint32]
cg.CGDisplayPixelsHigh.restype = ctypes.c_size_t
did = int(stream_cg_id)
cur_w, cur_h = cg.CGDisplayPixelsWide(did), cg.CGDisplayPixelsHigh(did)

dp_out = subprocess.run(["/opt/homebrew/bin/displayplacer", "list"], capture_output=True, text=True).stdout
ctx_to_pers = {}
for b in dp_out.split("Persistent screen id:")[1:]:
    pers_id = b.strip().splitlines()[0].strip()
    m = re.search(r"Contextual screen id:\s*(\d+)", b)
    if m:
        ctx_to_pers[m.group(1)] = pers_id
s_id = ctx_to_pers.get(stream_cg_id, stream_cg_id)
a_id = ctx_to_pers.get(apple_cg_id, apple_cg_id)
with open("/Users/runner/.stream_dp_ids", "w") as f:
    f.write(f"{s_id}\n{a_id}\n")

if str(cur_w) != target_w or str(cur_h) != target_h:
    for cmd in [
        ["/opt/homebrew/bin/displayplacer", f"id:{s_id}+{a_id} res:{target_w}x{target_h} scaling:off origin:(0,0) degree:0"],
        ["/opt/homebrew/bin/displayplacer", f"id:{s_id} res:{target_w}x{target_h} scaling:off origin:(0,0) degree:0"],
    ]:
        if subprocess.run(cmd, capture_output=True).returncode == 0:
            break
    cur_w, cur_h = cg.CGDisplayPixelsWide(did), cg.CGDisplayPixelsHigh(did)
print(f"  -> StreamDisplay (ID={stream_cg_id}) active at {cur_w}x{cur_h}")
PYEOF

if [ ! -x /usr/local/bin/set-res ]; then
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
fi

echo "=== [6/7] Ensuring SSH Server on ${TS_IP}:22 ==="
[ -f "$PERSIST_DIR/ssh/ssh_server.py" ] && [ ! -f "$HOME/ssh_server.py" ] && cp -p "$PERSIST_DIR/ssh/ssh_server.py" "$HOME/ssh_server.py"
[ -f "$PERSIST_DIR/ssh/ssh_host_ed25519" ] && [ ! -f "$HOME/.ssh_host_ed25519" ] && cp -p "$PERSIST_DIR/ssh/ssh_host_ed25519" "$HOME/.ssh_host_ed25519" && chmod 600 "$HOME/.ssh_host_ed25519"

if ! sudo lsof -nP -iTCP:22 -sTCP:LISTEN 2>/dev/null | grep -q "$TS_IP"; then
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
fi

echo "=== [7/7] Ensuring Sunshine & Restoring Moonlight Pairing Certificates ==="
mkdir -p "$HOME/.config/sunshine"
if ! pgrep -x sunshine >/dev/null 2>&1; then
  if [ -d "$PERSIST_DIR/sunshine" ] && [ -f "$PERSIST_DIR/sunshine/sunshine.conf" ]; then
    rsync -a "$PERSIST_DIR/sunshine/" "$HOME/.config/sunshine/"
  fi
fi

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

if ! pgrep -x sunshine >/dev/null 2>&1; then
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
  if [ ! -f "$HOME/.config/sunshine/sunshine_state.json" ]; then
    /opt/homebrew/bin/sunshine "$HOME/.config/sunshine/sunshine.conf" --creds "$SUN_USER" "$SUN_PASS"
  fi
fi

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

# Start Sunshine directly in background if devbox service hasn't spawned it within 5 seconds
if ! pgrep -x sunshine >/dev/null 2>&1; then
  sleep 4
  if ! pgrep -x sunshine >/dev/null 2>&1; then
    nohup "$HOME/run_sunshine.sh" >/tmp/sunshine-manual.log 2>&1 </dev/null &
    sleep 3
  fi
fi

rm -f /tmp/.persist_restore_in_progress

# Trigger an immediate snapshot to persistent storage
if [ -x "$WORKSPACE_DIR/sync_persist.sh" ]; then
  "$WORKSPACE_DIR/sync_persist.sh" --once
fi

echo "=========================================================="
echo " PERSISTENT ZURICH STREAMER READY!"
echo " Tailscale IP:     $TS_IP ($TS_FQDN)"
echo " Moonlight Host:   $TS_IP (Pairing preserved in /Volumes/devbox/persist/sunshine)"
echo " Sunshine Web UI:  https://${TS_IP}:47990  (${SUN_USER} / ${SUN_PASS})"
echo " SSH Command:      ssh ${SUN_USER}@${TS_IP}  (password: ${SUN_PASS})"
echo " Persistent Disk:  /Volumes/devbox (~/workspaces)"
echo "=========================================================="
