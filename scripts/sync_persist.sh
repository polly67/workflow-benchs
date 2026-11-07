#!/usr/bin/env bash
set -uo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

PERSIST_DIR="/Volumes/devbox/persist"
MODE="${1:---once}"

sync_to_persist() {
  # Guard: only back up once macOS user data / apps exist so a half-booted VM never overwrites good backups with empty dirs
  mkdir -p \
    "$PERSIST_DIR/Applications" \
    "$PERSIST_DIR/roblox-data/Preferences" \
    "$PERSIST_DIR/roblox-data/HTTPStorages" \
    "$PERSIST_DIR/roblox-data/Keychains" \
    "$PERSIST_DIR/prism-data/Preferences" \
    "$PERSIST_DIR/sunshine" \
    "$PERSIST_DIR/tailscale" \
    "$PERSIST_DIR/ssh" \
    "$PERSIST_DIR/betterdisplay" \
    "$PERSIST_DIR/installers"

  # 1. Applications (Roblox, Prism Launcher, BetterDisplay, or any custom app added by user)
  if [ -d "/Applications/Roblox.app" ]; then
    rsync -a --delete "/Applications/Roblox.app/" "$PERSIST_DIR/Applications/Roblox.app/" 2>/dev/null || true
  fi
  if [ -d "/Applications/Prism Launcher.app" ]; then
    rsync -a --delete "/Applications/Prism Launcher.app/" "$PERSIST_DIR/Applications/Prism Launcher.app/" 2>/dev/null || true
  elif [ -d "/Volumes/Prism Launcher 11.1.1/Prism Launcher.app" ] && [ ! -d "$PERSIST_DIR/Applications/Prism Launcher.app" ]; then
    rsync -a "/Volumes/Prism Launcher 11.1.1/Prism Launcher.app/" "$PERSIST_DIR/Applications/Prism Launcher.app/" 2>/dev/null || true
  fi
  if [ -d "/Applications/BetterDisplay.app" ] && [ ! -d "$PERSIST_DIR/Applications/BetterDisplay.app" ]; then
    rsync -a "/Applications/BetterDisplay.app/" "$PERSIST_DIR/Applications/BetterDisplay.app/" 2>/dev/null || true
  fi

  # 2. Roblox login cookies, Keychain auth token, WebKit data, settings & asset cache
  [ -d "$HOME/Library/Roblox" ] && rsync -a --delete "$HOME/Library/Roblox/" "$PERSIST_DIR/roblox-data/Library-Roblox/" 2>/dev/null || true
  [ -d "$HOME/Library/WebKit/com.roblox.RobloxPlayer" ] && rsync -a --delete "$HOME/Library/WebKit/com.roblox.RobloxPlayer/" "$PERSIST_DIR/roblox-data/WebKit-RobloxPlayer/" 2>/dev/null || true
  [ -d "$HOME/Library/Caches/com.roblox.RobloxPlayer" ] && rsync -a --delete "$HOME/Library/Caches/com.roblox.RobloxPlayer/" "$PERSIST_DIR/roblox-data/Caches-RobloxPlayer/" 2>/dev/null || true
  [ -d "$HOME/Library/HTTPStorages/com.roblox.RobloxPlayer" ] && rsync -a --delete "$HOME/Library/HTTPStorages/com.roblox.RobloxPlayer/" "$PERSIST_DIR/roblox-data/HTTPStorages/com.roblox.RobloxPlayer/" 2>/dev/null || true
  [ -f "$HOME/Library/HTTPStorages/com.roblox.RobloxPlayer.binarycookies" ] && cp -p "$HOME/Library/HTTPStorages/com.roblox.RobloxPlayer.binarycookies" "$PERSIST_DIR/roblox-data/HTTPStorages/" 2>/dev/null || true
  for pf in "$HOME/Library/Preferences"/com.roblox.*.plist; do
    [ -f "$pf" ] && cp -p "$pf" "$PERSIST_DIR/roblox-data/Preferences/" 2>/dev/null || true
  done
  if [ -f "$HOME/Library/Keychains/login.keychain-db" ]; then
    cp -p "$HOME/Library/Keychains/login.keychain-db" "$PERSIST_DIR/roblox-data/Keychains/login.keychain-db" 2>/dev/null || true
  fi

  # 3. Prism Launcher / Minecraft accounts, instances, mods & worlds
  if [ -d "$HOME/Library/Application Support/PrismLauncher" ]; then
    rsync -a --delete "$HOME/Library/Application Support/PrismLauncher/" "$PERSIST_DIR/prism-data/PrismLauncher/" 2>/dev/null || true
  fi
  for pf in "$HOME/Library/Preferences"/org.prismlauncher.*.plist; do
    [ -f "$pf" ] && cp -p "$pf" "$PERSIST_DIR/prism-data/Preferences/" 2>/dev/null || true
  done

  # 4. Sunshine config + Moonlight client pairing certificates (sunshine_state.json & credentials/)
  if [ -d "$HOME/.config/sunshine" ] && [ -f "$HOME/.config/sunshine/sunshine.conf" ]; then
    rsync -a --exclude="sunshine.log*" "$HOME/.config/sunshine/" "$PERSIST_DIR/sunshine/" 2>/dev/null || true
  fi

  # 5. Tailscale node identity (keeps exact same 100.71.119.113 IP across restarts)
  if sudo test -f "/Library/Tailscale/tailscaled.state" 2>/dev/null; then
    sudo cp -p "/Library/Tailscale/tailscaled.state" "$PERSIST_DIR/tailscale/tailscaled.state" 2>/dev/null || true
    sudo chown "$(id -un):staff" "$PERSIST_DIR/tailscale/tailscaled.state" 2>/dev/null || true
  fi

  # 6. SSH server script, host key & display state
  [ -f "$HOME/ssh_server.py" ] && cp -p "$HOME/ssh_server.py" "$PERSIST_DIR/ssh/ssh_server.py" 2>/dev/null || true
  [ -f "$HOME/.ssh_host_ed25519" ] && cp -p "$HOME/.ssh_host_ed25519" "$PERSIST_DIR/ssh/ssh_host_ed25519" 2>/dev/null || true
  [ -f "$HOME/Library/Preferences/pro.betterdisplay.BetterDisplay.plist" ] && cp -p "$HOME/Library/Preferences/pro.betterdisplay.BetterDisplay.plist" "$PERSIST_DIR/betterdisplay/" 2>/dev/null || true
  [ -d "$HOME/Library/Application Support/BetterDisplay" ] && rsync -a "$HOME/Library/Application Support/BetterDisplay/" "$PERSIST_DIR/betterdisplay/AppSupport/" 2>/dev/null || true

  # 7. Downloaded DMGs in ~/Downloads (optional convenience)
  for dmg in "$HOME/Downloads"/*.dmg; do
    [ -f "$dmg" ] && [ ! -f "$PERSIST_DIR/installers/$(basename "$dmg")" ] && cp -p "$dmg" "$PERSIST_DIR/installers/" 2>/dev/null || true
  done
}

if [ "$MODE" = "--loop" ]; then
  echo "[$(date -u +%FT%TZ)] Starting continuous 30s persistent storage sync to $PERSIST_DIR..."
  while true; do
    # Wait while initial boot restore is actively running
    if [ ! -f "/tmp/.persist_restore_in_progress" ]; then
      sync_to_persist
    fi
    sleep 30
  done
else
  sync_to_persist
  echo "[$(date -u +%FT%TZ)] Backed up Roblox, Prism Launcher, Sunshine pairing, Tailscale state & SSH keys to $PERSIST_DIR"
fi
