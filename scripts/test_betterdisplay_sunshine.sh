#!/bin/bash
set -x

echo "=================================================="
echo "🍏 Testing BetterDisplay Virtual Display & Sunshine"
echo "=================================================="

# 1. Install BetterDisplay & CLI
echo "--- Step 1: Installing BetterDisplay & CLI ---"
brew install --cask betterdisplay || true
brew install waydabber/betterdisplay/betterdisplaycli || true

# 2. Launch BetterDisplay App in background
echo "--- Step 2: Launching BetterDisplay App ---"
open -a BetterDisplay || /Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay &
sleep 5

# 3. Create and connect Virtual Display
echo "--- Step 3: Creating and connecting Virtual Screen via CLI ---"
betterdisplaycli create -deviceType=virtualScreen -virtualScreenName="CloudDisplay" -aspectWidth=16 -aspectHeight=9 || true
sleep 3
betterdisplaycli set -name="CloudDisplay" -connected=on || true
betterdisplaycli set -name="CloudDisplay" -resolution=1920x1080 || true
sleep 2

# Check Display status
echo "--- Checking Display Status ---"
betterdisplaycli get -identifiers || true
system_profiler SPDisplaysDataType || true

# 4. Install Sunshine
echo "--- Step 4: Installing Sunshine ---"
brew install lizardbyte/homebrew/sunshine || true

# Check Sunshine binary
which sunshine || ls -la /opt/homebrew/bin/sunshine || true

# 5. Configure Sunshine credentials
echo "--- Step 5: Configuring Sunshine ---"
mkdir -p ~/.config/sunshine
# Sunshine credentials helper if available
sunshine --creds admin "SunshineSecurePass123!" || true

# 6. Launch Sunshine test run (run for 20 seconds and capture logs)
echo "--- Step 6: Starting Sunshine Test Run (20 seconds) ---"
sunshine --version || true

# Run sunshine in background, record PID, and wait 20s
sunshine > /tmp/sunshine.log 2>&1 &
SUNSHINE_PID=$!
echo "Sunshine started with PID $SUNSHINE_PID"

# Wait 20 seconds while monitoring ports and logs
for i in {1..20}; do
  sleep 1
  echo -n "."
done
echo ""

# Check listening ports
echo "--- Checking Sunshine Ports (47989, 47990) ---"
netstat -an | grep -E "47989|47990" || lsof -i :47989 -i :47990 || true

# Print full Sunshine logs
echo "--- Sunshine Logs Output ---"
cat /tmp/sunshine.log

# Terminate test process
kill -9 $SUNSHINE_PID || true

# Save summary to results
mkdir -p results
cat << 'EOF' > results/betterdisplay_sunshine_summary.json
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "test_status": "completed"
}
EOF
cp /tmp/sunshine.log results/sunshine_run.log || true

echo "=================================================="
echo "🎉 BetterDisplay & Sunshine Test Complete"
echo "=================================================="
