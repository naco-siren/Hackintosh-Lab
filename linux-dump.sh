#!/usr/bin/env bash
#
# Dump everything worth keeping from Linux before switching to macOS only.
# Run on the target EliteBook 840 G5 while still booted into Ubuntu.
#
# Usage:
#   chmod +x linux-dump.sh
#   ./linux-dump.sh            # writes to ./hack-linux-dump-YYYYMMDD-HHMM/
#
# Will prompt for sudo once (lspci -vvv and dmidecode need root for full info).

set -u

OUT="hack-linux-dump-$(date +%Y%m%d-%H%M)"
mkdir -p "$OUT"
cd "$OUT" || exit 1

echo "[*] Writing dumps to: $PWD"
echo

# --- Warm up sudo so later commands don't re-prompt ---
sudo -v || { echo "sudo required"; exit 1; }

echo "[1/8] PCI tree (full, with BARs and capabilities)..."
sudo lspci -vvvnn                                               > lspci.txt 2>&1
lspci -tvnn                                                     > lspci-tree.txt 2>&1

echo "[2/8] USB topology..."
lsusb -tv                                                       > lsusb.txt 2>&1
lsusb -v 2>/dev/null                                            > lsusb-verbose.txt

echo "[3/8] DMI / BIOS / board info..."
sudo dmidecode                                                  > dmidecode.txt 2>&1

echo "[4/8] CPU info..."
cat /proc/cpuinfo                                               > cpuinfo.txt

echo "[5/8] dmesg (full)..."
sudo dmesg                                                      > dmesg.txt 2>&1
sudo dmesg | grep -iE 'i2c|syna|elan|atml|touchpad|trackpad'    > dmesg-i2c-touchpad.txt 2>&1

echo "[6/8] I2C devices (touchpad confirmation)..."
{
  echo "=== /sys/bus/i2c/devices/*/name ==="
  grep -H . /sys/bus/i2c/devices/*/name 2>/dev/null
  echo
  echo "=== ls /sys/bus/i2c/devices/ ==="
  ls -la /sys/bus/i2c/devices/ 2>/dev/null
  echo
  echo "=== i2cdetect per bus (if i2c-tools installed) ==="
  for bus in /sys/class/i2c-dev/i2c-*; do
    n="${bus##*i2c-}"
    echo "--- i2c-$n ---"
    sudo i2cdetect -y "$n" 2>/dev/null || echo "(i2cdetect not available or bus busy)"
  done
} > i2c.txt 2>&1

echo "[7/8] Thunderbolt state (Native+LP mode reference)..."
{
  echo "=== boltctl list ==="
  boltctl list 2>/dev/null || echo "(boltctl not installed)"
  echo
  echo "=== /sys/bus/thunderbolt/devices/ ==="
  ls -la /sys/bus/thunderbolt/devices/ 2>/dev/null || echo "(no thunderbolt sysfs entries)"
  echo
  echo "=== dmesg | grep thunderbolt ==="
  sudo dmesg | grep -iE 'thunderbolt|ICM|nhi|tbt'
} > thunderbolt.txt 2>&1

echo "[8/8] Battery + power supply info..."
{
  for p in /sys/class/power_supply/*/uevent; do
    echo "=== $p ==="
    cat "$p" 2>/dev/null
    echo
  done
} > battery.txt 2>&1

# --- Bonus: snapshot of ACPI table list (handy cross-ref with SSDTTime-Results) ---
echo "[bonus] ACPI table list..."
ls -la /sys/firmware/acpi/tables/ 2>/dev/null                   > acpi-tables.txt

echo
echo "Done. Outputs:"
ls -la
echo
echo "Next steps:"
echo "  1. Copy this '$PWD' directory onto your macOS install USB or external drive."
echo "  2. After you're fully on macOS, move it back into this repo (e.g. WIP/linux-dumps/) and commit."
