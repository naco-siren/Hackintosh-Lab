#!/usr/bin/env bash
#
# Run on the ProDesk (Catalina / Ventura) to capture everything about the Apple
# BCM943224PCIEBT2 card into one text file:
#   - Wi-Fi 14e4:4353 on RP07 (PciRoot(0x0)/Pci(0x1C,0x0)/Pci(0x0,0x0)): is the PCI device
#     there at all, which driver (if any) attached
#   - Bluetooth BCM20702 hub 0a5c:4500 + HCI 05ac:821f on XHC HS14: does it enumerate,
#     is HS14 present in the USB map
#   - kextstat, NVRAM boot-args, kernel log of this boot
#
# Usage:   bash wifi-bt-diagnose.sh
# Output:  ~/Desktop/wifi-bt-diagnose-YYYYMMDD-HHMM.txt   (copy it to the USB stick's EFI partition)

set -uo pipefail
OUT="$HOME/Desktop/wifi-bt-diagnose-$(date +%Y%m%d-%H%M).txt"

sec() { printf '\n===== %s =====\n' "$1"; }

{
  sec "System"
  sw_vers; uname -a
  echo "boot-args: $(nvram boot-args 2>&1)"
  csrutil status 2>&1

  sec "PCI: any Broadcom / 14e4 device?"
  ioreg -l -w0 -r -c IOPCIDevice 2>/dev/null \
    | grep -E '^\s*\+-o |"vendor-id"|"device-id"|"subsystem-id"|"IOName"|"pcidebug"|"compatible"' \
    | grep -B4 -A4 -i -E 'e4140000|53430000|14e4|ARPT|PXSX@0' || echo "(no 14e4 PCI device found -> card not visible on PCIe at all)"

  sec "PCI: RP07 subtree (Wi-Fi slot, 00:1c.0)"
  ioreg -w0 -r -n RP07 2>/dev/null | head -40 || echo "(no RP07)"

  sec "Wi-Fi driver objects"
  ioreg -l -w0 2>/dev/null | grep -E '^\s*\+-o .*(AirPort|Brcm|IO80211|ARPT)' | head -30 || true
  system_profiler SPAirPortDataType 2>&1 | head -60
  networksetup -listallhardwareports 2>&1

  sec "USB: device tree (look for BRCM20702 Hub / Bluetooth USB Host Controller)"
  ioreg -p IOUSB -w0 2>/dev/null

  sec "USB: XHC ports actually created (expect HS01-05 HS13 HS14 SS01-05 SS07)"
  ioreg -w0 -r -n XHC 2>/dev/null | grep -E '\+-o (HS|SS|USR)[0-9]+@'
  echo "--- HS14 detail"
  ioreg -l -w0 -r -n HS14 2>/dev/null | grep -E '\+-o|UsbConnector|"port"|port-count|"name"' | head -20 || echo "(HS14 not present -> USBMap did not apply / BT port dropped)"

  sec "Bluetooth"
  system_profiler SPBluetoothDataType 2>&1 | head -60

  sec "kextstat (Wi-Fi / BT / USB / Lilu family)"
  kextstat 2>/dev/null | grep -i -E 'airport|80211|brcm|bluetooth|usbmap|usbhost|lilu|whatevergreen|applealc|virtualsmc|mausi|nvmefix'

  sec "Kernel log this boot (airport/brcm/bluetooth/usb errors)"
  log show --last boot --style compact --predicate 'process == "kernel"' 2>/dev/null \
    | grep -i -E 'airport|brcm|bcm|80211|arpt|bluetooth|HS14|usb.*(error|fail)|pci.*(error|fail)' | head -200
} > "$OUT" 2>&1

echo "written: $OUT ($(wc -l < "$OUT") lines)"
