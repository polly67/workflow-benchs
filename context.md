# Complete Project Context & Technical Log (`context.md`)

This document records **everything** designed, debugged, configured, built, and deployed across this project:
1. **Low-latency macOS Cloud Streaming Host** running **Sunshine + BetterDisplay + `displayplacer` + Custom SSHv2 Server over Tailscale** on **Namespace Apple M5 Pro (`nscloud-macos-sequoia-stable-arm64-6x14`)** via GitHub Actions.
2. **Custom `Moonlight WASD` Android Client (`Moonlight-WASD.apk`)** cloned and compiled from `moonlight-stream/moonlight-android` with native **WASD Joystick**, **Mouse-Look Right Stick**, **21 remappable keyboard/mouse slots**, and **unlimited draggable/resizable custom floating key buttons**.

---

## 1. End-to-End System Architecture

```text
+-----------------------------------------------------------------------------------+
| Android Device — Custom "Moonlight WASD" APK (com.limelight.unofficial)           |
|  - On-Screen WASD Stick + Custom Key Buttons + Physical Gamepad Mapper            |
|  - Sends native GFE Keyboard (0x8000|VK_*) + Mouse Move/Click over Tailscale      |
+-----------------------------------------+-----------------------------------------+
                                          |
                          Tailscale WireGuard Mesh (UDP/TCP)
                                          |
+-----------------------------------------v-----------------------------------------+
| GitHub Actions Runner — Namespace macOS Sequoia 15.7.5 (Apple M5 Pro, 6x14)       |
|  Runner Label: nscloud-macos-sequoia-stable-arm64-6x14 (US-East / Leesburg, VA)   |
|                                                                                   |
|  1. Display Layer:                                                                |
|     - BetterDisplay virtual screen ("StreamDisplay", CGDirectDisplayID=3)         |
|     - displayplacer mirrors Apple Virtual -> StreamDisplay at 1280x720 scaling:off|
|       (True 1:1 non-HiDPI framebuffer; eliminates 3840x2160 4K Retina overhead)   |
|     - /usr/local/bin/set-res helper for live resolution changes over SSH          |
|                                                                                   |
|  2. Streaming & Input Host (Sunshine):                                            |
|     - Native TCC Screen Capture pre-granted on Sequoia Stable (zero VNC setup!)   |
|     - Hardware VideoToolbox H.264 & HEVC (vt_realtime=enabled, vt_coder=cavlc)    |
|     - CoreGraphics keyboard & mouse injection (native, zero-license)              |
|     - Web UI at https://<tailscale-ip>:47990 (runner / root, CSRF pre-verified)   |
|                                                                                   |
|  3. Terminal Access (scripts/ssh_server.py):                                      |
|     - AsyncSSH RFC-4253 SSHv2 server on TCP port 22 (runner / root)               |
|     - Drops privileges to local macOS runner user; supports PTY, exec, SFTP, SCP  |
+-----------------------------------------------------------------------------------+
```

---

## 2. Repository Files & Artifacts

| Path / URL | Purpose |
| :--- | :--- |
| `.github/workflows/sunshine-macos-tailscale.yml` | Complete GitHub Actions workflow provisioning BetterDisplay, `displayplacer`, `AsyncSSH`, Tailscale, and Sunshine on `nscloud-macos-sequoia-stable-arm64-6x14` (or `macos-latest`). |
| `scripts/ssh_server.py` | Standalone Python `asyncssh` SSHv2 server listening on port `22` with username `runner` and password `root`, PTY resize (`TIOCSWINSZ`), non-PTY command execution, SFTP, and SCP. |
| `scripts/test_betterdisplay_sunshine.sh` | Initial probe script that validated BetterDisplay virtual monitor creation + Sunshine VideoToolbox encoder detection on headless macOS. |
| `scripts/gpu_test.swift`, `scripts/gpu_3d_render.swift`, `scripts/gpu_benchmark.py`, `scripts/comprehensive_benchmark.py` | Metal GPU compute & offscreen 3D rendering benchmarks verifying Apple Silicon paravirtualized Metal hardware acceleration on macOS runners. |
| `moonlight-android/` | Cloned `moonlight-stream/moonlight-android` repository customized with `WasdKeyMapper.java`, `CustomKeyButton.java`, live `KEYS` overlay menu, and release signing. |
| `Moonlight-WASD.apk` | Compiled, R8-optimized, v1+v2 signed universal Android APK (`11.1 MB`, `arm64-v8a` / `armeabi-v7a` / `x86` / `x86_64`). |
| `https://github.com/polly67/workflow-benchs/releases/download/v1.0-moonlight-wasd/Moonlight-WASD.apk` | Direct public GitHub Release download URL (`tag: v1.0-moonlight-wasd`). |

---

## 3. Chronological Engineering Log & Root-Cause Solutions

### Phase 1: GPU & Headless Virtual Display Verification
- **Goal**: Confirm macOS CI VMs have real Apple Silicon Metal GPU + VideoToolbox hardware encoding and can expose a custom-resolution virtual display to Sunshine.
- **Findings**:
  - Compiled and ran Swift Metal compute & 3D shader benchmarks (`scripts/gpu_test.swift`, `scripts/gpu_3d_render.swift`), confirming hardware-accelerated Apple Paravirtualized Metal GPU + `h264_videotoolbox` / `hevc_videotoolbox` encoders.
  - Verified `BetterDisplay` + `betterdisplaycli` creates a software-defined virtual monitor (`StreamDisplay`) selectable by Sunshine via CoreGraphics `CGDirectDisplayID` (`output_name = <id>`).

### Phase 2: Fixing SSH (`runner` / `root`) on macOS (`eDSAuthFailed -14090`)
- **Problem**: Attempting to change the macOS `runner` user's OS password to `root` via `sudo dscl . -passwd /Users/runner root` or `sysadminctl` failed with:
  ```text
  passwd: DS error: eDSAuthFailed
  <dscl_cmd> DS Error: -14090 (eDSAuthFailed)
  ```
  because macOS Apple Silicon VMs protect the `runner` login keychain / SecureToken against changing the password without knowing the randomized provisioning password, blocking macOS's built-in `/usr/sbin/sshd` password authentication.
- **Solution (`scripts/ssh_server.py`)**:
  - Built a full RFC-4253 SSHv2 server in Python using `asyncssh` (`$HOME/.ssh-venv`).
  - Binds port `22` as root (after unloading `system/com.openssh.sshd`), authenticates `runner` / `root` via both `password` and `keyboard-interactive` auth, and drops privileges (`os.setgroups`, `os.setgid`, `os.setuid`) to the actual local `runner` user before spawning `/bin/zsh -l` inside a real `pty.openpty()` terminal.
  - Supports interactive shells, terminal window resizing, single-command `ssh runner@<ip> "cmd"`, `scp`, and `sftp`.
  - Added an automated PTY `ssh runner@127.0.0.1` self-test step in the workflow to guarantee SSH works before going live.

### Phase 3: Fixing Sunshine Web UI `CSRF Protection Error`
- **Problem**: Opening `https://<tailscale-ip>:47990` to pair Moonlight's PIN failed with:
  > `CSRF Protection Error: The request was blocked by CSRF protection. If you are accessing Sunshine from a non-default URL or reverse proxy, add that origin to the 'csrf_allowed_origins' option in your configuration.`
- **Root Cause**: Inspected `LizardByte/Sunshine` `src/config.cpp` (`string_list_f` parser). Sunshine parses `csrf_allowed_origins` as a **comma-separated** list of exact `https://<host>:47990` origins (not JSON array, not space-separated) and requires `origin_web_ui_allowed = wan` for non-LAN (`100.x.y.z` CGNAT Tailscale) interfaces.
- **Solution**:
  - Dynamically queried Tailscale IPv4 (`100.x.y.z`), IPv6, MagicDNS FQDN (`*.ts.net`), `.local` hostname, `localhost`, and `127.0.0.1`, generating comma-separated `https://<host>:47990,https://<host>` entries in `~/.config/sunshine/sunshine.conf`.
  - Added an automated `curl -X POST https://<tailscale-ip>:47990/api/pin` preflight test sending `Origin: https://<tailscale-ip>:47990` to verify `csrf_preflight: passed_200` on every run.

### Phase 4: Fixing BetterDisplay Cask CLI Hang & Tailscale DNS Blackhole
- **Problem 1 (BetterDisplay CLI Hang)**: Homebrew's `betterdisplay` cask installs a symlink wrapper at `/opt/homebrew/bin/betterdisplaycli` pointing into `BetterDisplay.app/Contents/MacOS/BetterDisplay`, which synchronously launches a second GUI instance and hangs CI steps indefinitely when stdout/stderr pipes stay open.
  - **Fix**: Removed `/opt/homebrew/bin/betterdisplaycli` after installing the cask, installed the standalone `waydabber/betterdisplay/betterdisplaycli` formula (`brew link --overwrite betterdisplaycli`), and launched `BetterDisplay.app` detached (`>/tmp/betterdisplay.log 2>&1 </dev/null &`).
- **Problem 2 (Tailscale Overwriting macOS DNS)**: After `tailscale/github-action@v4` ran, macOS DNS resolvers were set solely to `100.100.100.100`, causing public DNS lookups (including `results-receiver.actions.githubusercontent.com` in `actions/upload-artifact@v4` and Safari browsing) to fail with `ENOTFOUND`.
  - **Fix**: Installed all Homebrew & Python packages **before** connecting Tailscale, and immediately after Tailscale connects ran `sudo tailscale set --accept-dns=false` + `sudo networksetup -setdnsservers <service> 1.1.1.1 8.8.8.8 100.100.100.100` + `dscacheutil -flushcache`.

### Phase 5: Eliminating Stream Lag (9x Hidden 4K Retina Framebuffer Fix + Namespace M5 Pro)
- **Root Causes of Initial Lag**:
  1. **Geographic Latency**: GitHub's `macos-latest` runners were landing in US-West (`California`) on older 3-core Apple M1 VMs (~160+ ms RTT to Europe).
  2. **Hidden 4K Retina Scaling**: BetterDisplay created `StreamDisplay` as a HiDPI Retina display backed by a **`3840x2160` (4K)** pixel buffer while keeping `Apple Virtual` active as a second extended screen!
  3. **macOS Compositor Overhead**: macOS Spotlight indexing (`mds_stores`), transparency/blur, and window animations consumed CPU/GPU frame budget.
- **Solutions Implemented**:
  1. **Switched to Namespace (`namespace.so`) Runners**: Connected Namespace GitHub App (`6 vCPU Apple M5 Pro, 14 GB RAM`) running in US-East (`Leesburg, Virginia`, `iad3` — cutting transatlantic latency in half vs California; EU data residency can also be toggled in `https://cloud.namespace.so/workspace/settings` or via `support@namespace.so`).
  2. **Enforced True 1:1 Non-HiDPI `1280x720` Mirroring via `displayplacer`**:
     - Created `StreamDisplay` with `-virtualScreenHiDPI=off`.
     - Mapped CoreGraphics contextual IDs to `displayplacer` persistent UUIDs and executed:
       ```bash
       displayplacer "id:${STREAM_UUID}+${APPLE_UUID} res:1280x720 scaling:off origin:(0,0) degree:0"
       ```
     - Verified via `CoreGraphics.CGDisplayPixelsWide` / `CGDisplayPixelsHigh` that the real pixel buffer is **`1280x720` (`resolution_scale: 100/100`)** — **9x fewer pixels** than `3840x2160`!
     - Installed `/usr/local/bin/set-res` (e.g. `set-res 1920x1080` or `set-res 1280x720`) for instant live resolution switching over SSH.
  3. **Tuned Sunshine VideoToolbox Realtime Encoding & Debloated macOS**:
     - Disabled Spotlight (`sudo mdutil -a -i off`), software auto-updates, Dock animations, window animations, and transparency (`reduceTransparency -bool true`).
     - Set `encoder = videotoolbox`, `vt_coder = cavlc`, `vt_realtime = enabled`, `vt_software = disabled`, `fec_percentage = 5`, `qp = 26`, `min_threads = 2`.

### Phase 6: Solving `failed to initialize capture/encoding` Natively (`macos-sequoia-stable`)
- **Problem**: On `nscloud-macos-tahoe-arm64-6x14` (macOS 26 Tahoe), Homebrew Needed `brew update --quiet` (due to removed `on_macos` Cask DSL in older Brew) and once installed, Sunshine failed Moonlight stream initialization with:
  ```text
  Error: No screen capture permission! Please activate it in 'System Preferences' -> 'Privacy' -> 'Screen Recording'
  ```
  because Namespace's Tahoe 26 image did not pre-seed `kTCCServiceScreenCapture` in `TCC.db`.
- **Breakthrough Solution**:
  - Tested Namespace's **`nscloud-macos-sequoia-stable-arm64-6x14`** (**macOS Sequoia 15.7.5** on **Apple M5 Pro**).
  - Namespace's `macos-sequoia-stable` image **pre-grants macOS Screen Recording & Accessibility TCC permissions natively out of the box** (just like GitHub's `macos-latest`)!
  - Sunshine preflight immediately logged:
    - `screen_capture_status: granted_natively`
    - `Found H.264 encoder: h264_videotoolbox [videotoolbox]`
    - `Found HEVC encoder: hevc_videotoolbox [videotoolbox]`
  - Boot-to-stream time dropped to **~2 minutes 15 seconds** with **zero VNC clicks required**.

---

## 4. Custom `Moonlight WASD` Android Client (`moonlight-android`)

### Why We Built a Custom Moonlight APK
On Apple Silicon macOS, Apple restricts virtual game controller creation (`IOHIDUserDevice` / `HIDVirtualDevice`) behind a private corporate entitlement (`com.apple.developer.hid.virtual.device`). As a result, Sunshine on macOS logs `Warning: No gamepad input is available` unless a paid LizardByte `libvirtualhid` broker license is installed. Meanwhile, **CoreGraphics keyboard and mouse input on macOS Sequoia works 100% natively and for free**.

To make mobile gaming on macOS runners effortless without any host drivers or paid licenses, we cloned `https://github.com/moonlight-stream/moonlight-android.git` (with all JNI native submodules: `moonlight-common-c`, `opus`, `dav1d`, `openssl`, `nanors`) into `/home/eouser/testmac/moonlight-android` and built **`Moonlight WASD`**.

### Files Created & Modified in `moonlight-android/`

1. **`app/src/main/java/com/limelight/binding/input/virtual_controller/WasdKeyMapper.java` (NEW — 645 lines)**:
   - **Full Virtual-Key & Mouse Catalog (`BindableAction`)**: Encodes standard GFE keyboard wire codes (`(short)((0x80 << 8) | vkCode)`) for `A–Z`, `0–9`, `F1–F12`, `Space`, `Left Shift`, `Left Ctrl`, `Left Alt`, `Command/Win`, `Tab`, `Esc`, `Enter`, `Backspace`, `Caps Lock`, `Arrow Keys`, navigation/punctuation keys, `Mouse Left/Right/Middle/Side Clicks`, and `Mouse Scroll Up/Down`.
   - **8-Way WASD Left Stick Translation**: Converts analog `(leftStickX, leftStickY)` to `W / A / S / D` (or any custom 4 keys) using hysteresis thresholds (`0.35` engage, `0.27` release) for crisp cardinal and 45-degree diagonal (`W+D`, `W+A`, `S+D`, `S+A`) movement.
   - **60Hz Right Stick Modes**:
     - `Mouse Look` (default): 16ms `Looper.getMainLooper()` loop applying a quadratic response curve (`mag^2 * sensitivity`) with 4 speed presets (`Low=7`, `Medium=14`, `High=22`, `Ultra=32`).
     - `Arrow Keys`, `I/J/K/L`, or `Disabled`.
   - **21 Remappable Slots**:
     - Defaults: `LS=W/A/S/D`, `A=Space`, `B=C`, `X=R`, `Y=F`, `RT=Left Click`, `LT=Right Click`, `RB=E`, `LB=Q`, `L3=Left Shift`, `R3=Left Ctrl`, `D-Pad=1/2/3/4`, `Start=Esc`, `Back=Tab`, `Guide=M`.
   - **Reference-Counted Dispatch & Modifier State**: Tracks reference counts across simultaneous sources (so overlapping custom buttons and standard buttons never prematurely release a held key), maintains active modifier bitmasks (`MODIFIER_SHIFT`, `MODIFIER_CTRL`, `MODIFIER_ALT`, `MODIFIER_META`), and guarantees `releaseAll()` on mode switch or stream disconnect (zero stuck keys).
   - **In-Stream UI Menu (`showMainConfigDialog`)**: Allows toggling WASD vs Gamepad mode, adding/deleting custom floating buttons, remapping any of the 21 slots, changing Right Stick speed/mode, and resetting defaults—persisted in `SharedPreferences` (`WASD_KEY_MAP_PREFS`).

2. **`app/src/main/java/com/limelight/binding/input/virtual_controller/CustomKeyButton.java` (NEW)**:
   - Extends `DigitalButton` to create user-spawned floating buttons (`elementId >= 1000`) supporting both **Normal Press & Hold** and **Sticky Toggle (`*`)** (tap once to hold key down, tap again to release).

3. **`app/src/main/java/com/limelight/binding/input/ControllerHandler.java` (MODIFIED)**:
   - Instantiates `WasdKeyMapper` and hooks `sendControllerInputPacket(...)` so **both** On-Screen Virtual Controls (`reportOscState`) **and** physical Bluetooth/USB gamepads automatically route through `WasdKeyMapper` when enabled (sending zeroed gamepad frames alongside keyboard/mouse packets to prevent double input). Calls `wasdKeyMapper.releaseAll()` / `destroy()` on teardown.

4. **`app/src/main/java/com/limelight/binding/input/virtual_controller/VirtualController.java` (MODIFIED)**:
   - Enabled `frame_layout.setMotionEventSplittingEnabled(true)` for simultaneous multi-touch across joystick and buttons.
   - Added a translucent **`KEYS`** pill button (`buttonKeyConfig`) at top-left next to the **Gear** Move/Resize button to open `WasdKeyMapper` live during a stream.

5. **`app/src/main/java/com/limelight/binding/input/virtual_controller/VirtualControllerConfigurationLoader.java` (MODIFIED)**:
   - Dynamically labels all on-screen buttons with their active bound key (`SPC`, `C`, `R`, `F`, `LMB`, `RMB`, `Q`, `E`, `SHFT`, `CTRL`, `TAB`, `ESC`, `M`) when WASD mode is enabled.
   - Places `L3` (`SHFT`) and `R3` (`CTRL`) on the default layout so Sprint and Crouch are accessible without double-tapping sticks.
   - Instantiates and restores saved screen coordinates/sizes for all user-added `CustomKeyButton` elements.

6. **`LeftAnalogStick.java` & `DigitalPad.java` (MODIFIED)**:
   - Renders live directional key labels (`W / A / S / D` on Left Stick ring; `1 / 2 / 3 / 4` on D-Pad arms) when WASD mode is active.

7. **`PreferenceConfiguration.java`, `res/xml/preferences.xml` & `app/build.gradle` (MODIFIED)**:
   - Set `ONSCREEN_CONTROLLER_DEFAULT = true` so the WASD overlay appears immediately on first install.
   - Set release `app_label` to **`Moonlight WASD`** (`applicationId: com.limelight.unofficial` with parameterized `poster.${applicationId}` ContentProvider authority) so it installs side-by-side with official Play Store Moonlight without conflicts.
   - Configured PKCS12 release signing (`app/moonlight-wasd.jks`) and compiled universal release APK:
     ```bash
     cd /home/eouser/testmac/moonlight-android
     JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
     ANDROID_HOME=/home/eouser/Android/Sdk \
     ./gradlew assembleNonRootRelease --no-daemon
     ```
   - Verified v1 (JAR) + v2 APK signatures via `apksigner verify` and published to GitHub Releases (`v1.0-moonlight-wasd`).

---

## 5. Quick-Start & Operations Reference

### A. Start a New macOS Sequoia Streamer Session
Trigger `.github/workflows/sunshine-macos-tailscale.yml` from the GitHub Actions tab (`Run workflow`) or via REST API / `gh`:
```bash
gh workflow run sunshine-macos-tailscale.yml \
  --repo polly67/workflow-benchs \
  -f runner_label="nscloud-macos-sequoia-stable-arm64-6x14" \
  -f tailscale_authkey="<YOUR_TAILSCALE_AUTH_KEY>" \
  -f sunshine_user="runner" \
  -f sunshine_password="root" \
  -f display_width="1280" \
  -f display_height="720"
```
After ~2 minutes, check the **`sunshine-connection-info`** artifact (or Step 9 log) for the Tailscale IP (`100.x.y.z`):
- **Sunshine Web UI (PIN Pairing)**: `https://<tailscale-ip>:47990` (`runner` / `root`)
- **SSH Terminal**: `ssh runner@<tailscale-ip>` (password: `root`)
- **Change Stream Resolution Live (via SSH)**:
  ```bash
  set-res 1920x1080   # Switch to 1080p 1:1 non-HiDPI
  set-res 1280x720    # Switch back to 720p 1:1 non-HiDPI
  ```

### B. Using `Moonlight WASD` on Android
1. Install **`Moonlight-WASD.apk`**:
   `https://github.com/polly67/workflow-benchs/releases/download/v1.0-moonlight-wasd/Moonlight-WASD.apk`
2. Add your runner's Tailscale IP in **Moonlight WASD**, enter the 4-digit PIN at `https://<tailscale-ip>:47990`, and launch **Desktop**.
3. Use the **top-left buttons** on the stream overlay:
   - **`KEYS`**: Toggle WASD vs Gamepad mode, remap any joystick direction or button to any PC key/mouse button, adjust Right Stick mouse speed, or tap **`+ Add Custom Key Button to Screen`** (normal hold or sticky toggle).
   - **Gear Icon**: Tap once to **Move** any button/stick by dragging, tap again to **Resize**, and tap a third time to **Save** your custom layout.
