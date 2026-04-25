#!/usr/bin/env bash
#
# Run on the target Hackintosh (Big Sur). One-shot script that:
#   1. Lists currently attached USB devices so you can unplug the
#      bothersome ones (ADATA stick etc) before sleep test.
#   2. Applies pmset settings that disable wake-on-network, TCP
#      keepalive, hibernate, standby — all the silent sleep-killers.
#   3. Captures a pre-test snapshot of pmset state and IOKit
#      assertions.
#   4. Pauses for you to close + open the lid.
#   5. Captures post-test pmset log + assertions + recent system
#      log around sleep/wake.
#   6. Auto-zips the whole capture for AirDrop back to the dev Mac.
#
# Usage on Hackintosh:
#   bash sleep-diagnose.sh
#
# Output: ~/Desktop/sleep-diagnose-YYYYMMDD-HHMM.zip

set -uo pipefail

OUT="$HOME/Desktop/sleep-diagnose-$(date +%Y%m%d-%H%M)"
mkdir -p "$OUT"
cd "$OUT"

echo "[*] Output dir: $OUT"
echo

# Warm up sudo
echo "[*] Need sudo for pmset and log access. Enter password if prompted:"
sudo -v || { echo "sudo required, abort"; exit 1; }

echo
echo "===== STEP 1: USB inventory =====" | tee -a session.log
echo "Attached USB devices (anything non-internal you should consider unplugging):" | tee -a session.log
ioreg -p IOUSB -l 2>/dev/null | grep -E "USB Product Name|locationID" | head -40 | tee usb-inventory.txt
echo "(saved usb-inventory.txt)"
echo
read -p "Have you unplugged the ADATA USB stick (and any non-essential USB)? Press ENTER to continue, Ctrl+C to abort: " _

echo
echo "===== STEP 2: Apply pmset disable-wake-sources settings =====" | tee -a session.log
sudo pmset -a womp 0                  2>&1 | tee -a session.log
sudo pmset -a tcpkeepalive 0          2>&1 | tee -a session.log
sudo pmset -a networkoversleep 0      2>&1 | tee -a session.log
sudo pmset -a powernap 0              2>&1 | tee -a session.log
sudo pmset -a hibernatemode 0         2>&1 | tee -a session.log
sudo pmset -a standby 0               2>&1 | tee -a session.log
sudo pmset -a autopoweroff 0          2>&1 | tee -a session.log
sudo pmset -a proximitywake 0         2>&1 | tee -a session.log   # NEW: disable Continuity proximity wake (BT)
sudo pmset -a sleepservicestimeout 1  2>/dev/null | tee -a session.log || true   # NEW: shrink Sleep Services window
sudo pmset -a darkwakes 0             2>/dev/null | tee -a session.log || true   # legacy key, may not exist on Big Sur

# Note: macOS deliberately uses Dark Wake on AC for push/AirDrop maintenance — pmset
# can't fully forbid it on AC. Battery has more aggressive policy and will reach S3
# faster. Iter 4 explicitly tests on BATTERY for that reason.

# Save the resulting pmset state for review
pmset -g > pmset-settings.txt
echo "(saved pmset-settings.txt)"

echo
echo "===== STEP 3: Pre-sleep snapshots ====="
pmset -g assertions > assertions-pre.txt
echo "(saved assertions-pre.txt)"

echo
echo "===== STEP 4: Lid-close test ====="
echo
echo "INSTRUCTIONS:"
echo "  1. Save any work in other apps. Quit Music, Safari, browsers — anything that holds Audio/Network assertions."
echo "  2. **UNPLUG THE AC POWER ADAPTER** — Iter 4 specifically tests on battery. macOS uses Dark Wake"
echo "     on AC for push/AirDrop maintenance, which can prevent transition to deep S3 indefinitely. Battery"
echo "     mode has more aggressive sleep policy."
echo "  3. CLOSE THE LAPTOP LID."
echo "  4. WAIT AT LEAST 90 SECONDS — this gives sleep enough time to settle and any wake event to fire."
echo "  5. OPEN THE LID."
echo "  6. Plug AC back in if you want to charge / continue."
echo "  7. Come back to this Terminal."
echo
echo "Observe and remember:"
echo "  - Did the power LED start to BREATHE within ~5 seconds of lid close (real S3 sleep)?"
echo "  - Or did the LED stay solid (Dark Wake stuck — same as Iter 3)?"
echo "  - Did opening the lid wake the screen, or did you have to press the power button?"
echo
read -p "Press ENTER once you're back from the lid-close test: " _

echo
echo "===== STEP 5: Post-sleep capture ====="

sudo pmset -g log | tail -300 > pmset-log-tail.txt
sudo pmset -g log | grep -iE "sleep|wake|denied|XDCI|XHCI|^[0-9]{4}.*Wake|^[0-9]{4}.*DarkWake" | tail -120 > pmset-sleep-wake-events.txt
pmset -g assertions > assertions-post.txt

log show --last 10m --predicate 'eventMessage CONTAINS "sleep" OR eventMessage CONTAINS "wake" OR eventMessage CONTAINS "powerd" OR eventMessage CONTAINS "XDCI"' 2>/dev/null > syslog-sleep-wake.txt

echo "(saved pmset-log-tail.txt, pmset-sleep-wake-events.txt, assertions-post.txt, syslog-sleep-wake.txt)"

echo
echo "===== STEP 6: Quick on-screen summary =====" | tee -a session.log
echo
echo "[Last 8 sleep/wake events from pmset log:]" | tee -a session.log
sudo pmset -g log | grep -E "^[0-9]{4}-.*(Sleep|Wake|DarkWake)" | tail -8 | tee -a session.log
echo

echo "[Currently held kernel power assertions:]" | tee -a session.log
pmset -g assertions | grep -A1 "Kernel Assertions" | head -8 | tee -a session.log
echo

echo "===== Done ====="
echo

# Auto-zip
ZIP="$HOME/Desktop/sleep-diagnose-$(date +%Y%m%d-%H%M).zip"
( cd "$HOME/Desktop" && zip -qr "$ZIP" "$(basename "$OUT")" )
echo "Bundle: $ZIP"
echo "(drag this zip to AirDrop, send to your dev Mac)"
