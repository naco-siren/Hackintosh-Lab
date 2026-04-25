#!/usr/bin/env bash
#
# Run on the target Hackintosh (Big Sur) anytime to capture
# everything trackpad-related into a single AirDroppable text file:
#   - IOReg around the TPD0 ACPI device + I2C bus
#   - VoodooI2C / VoodooInput / VoodooPS2 IOKit registry sections
#   - kextstat for trackpad-related kexts
#   - System Information for the touchpad USB device (the
#     0x138a:0x00ab Synaptics raw-HID node)
#   - Recent system log mentions of trackpad / Voodoo / TPD0
#   - Trackpad user defaults (System Settings configuration)
#
# Usage on Hackintosh:
#   bash trackpad-diagnose.sh
#
# Output: ~/Desktop/trackpad-diagnose-YYYYMMDD-HHMM.txt

set -uo pipefail

OUT="$HOME/Desktop/trackpad-diagnose-$(date +%Y%m%d-%H%M).txt"

{
  echo "===== Section 1: TPD0 / I2C0 ACPI device ====="
  echo
  ioreg -l -w 0 2>/dev/null | grep -B2 -A40 "TPD0@" || echo "(TPD0 not found in IOReg — trackpad may be matched under a different ACPI path)"
  echo
  echo "----- I2C0 bus and children -----"
  ioreg -l -w 0 2>/dev/null | grep -B2 -A30 "I2C0@" | head -100

  echo
  echo "===== Section 2: VoodooI2C / VoodooInput / VoodooPS2 ====="
  echo
  ioreg -l -w 0 2>/dev/null | grep -B2 -A30 "VoodooI2C\|VoodooInput\|VoodooPS2" | head -300

  echo
  echo "===== Section 3: Synaptics / 0x138a / SYNA matches ====="
  echo
  ioreg -l -w 0 2>/dev/null | grep -B2 -A20 -i "synaptics\|0x138a\|SYNA\|0x00ab" | head -200

  echo
  echo "===== Section 4: USB devices (the trackpad reports as 0x138a:0x00ab here) ====="
  echo
  ioreg -p IOUSB -l -w 0 2>/dev/null | head -300

  echo
  echo "===== Section 5: kextstat — currently loaded trackpad-related kexts ====="
  echo
  kextstat 2>/dev/null | grep -iE "voodoo|hid|synap|i2c|input" || echo "(none matched)"

  echo
  echo "===== Section 6: HID devices known to macOS ====="
  echo
  ioreg -p IOService -l -w 0 2>/dev/null | grep -B1 -A10 "AppleHIDInterface\|AppleUserHIDDevice\|IOHIDInterface" | head -150

  echo
  echo "===== Section 7: System log — last 10 min trackpad / Voodoo / TPD0 mentions ====="
  echo
  log show --last 10m --predicate 'eventMessage CONTAINS "trackpad" OR eventMessage CONTAINS "Voodoo" OR eventMessage CONTAINS "TPD0" OR eventMessage CONTAINS "Synaptics" OR eventMessage CONTAINS "MultitouchSupport"' 2>/dev/null | head -300 || echo "(log show failed)"

  echo
  echo "===== Section 8: User trackpad preferences (System Settings) ====="
  echo
  echo "----- com.apple.AppleMultitouchTrackpad -----"
  defaults read com.apple.AppleMultitouchTrackpad 2>/dev/null || echo "(not set)"
  echo
  echo "----- com.apple.driver.AppleBluetoothMultitouch.trackpad -----"
  defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad 2>/dev/null || echo "(not set)"
  echo
  echo "----- NSGlobalDomain trackpad scaling -----"
  defaults read NSGlobalDomain com.apple.trackpad.scaling 2>/dev/null || echo "(not set)"

  echo
  echo "===== Section 9: System Profiler USB section ====="
  echo
  system_profiler SPUSBDataType 2>/dev/null | grep -B2 -A8 "0x138a\|0x00ab\|Synaptics\|trackpad" | head -60 || echo "(no Synaptics device in system_profiler USB)"

} > "$OUT" 2>&1

echo "Saved to: $OUT"
echo "Size: $(stat -f %z "$OUT") bytes"
echo
echo "AirDrop the file to your dev Mac for analysis."
