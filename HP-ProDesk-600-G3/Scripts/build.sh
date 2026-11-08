#!/bin/bash
# Assemble OpenCore EFIs for HP ProDesk 600 G3 DM -> macOS Catalina + Ventura.
#
# Both flavours come from the same make_config.py; they differ only in binaries and debug knobs:
#   DEBUG   = DEBUG OpenCore + DEBUG acidanthera kexts, -v -liludbgall, OC log file (Target 67)
#   RELEASE = RELEASE OpenCore + RELEASE kexts, no -v, AppleDebug off, Target 3 (Dortania Post-Install)
#
# Layered like the EliteBook EFIs (<macOS>/<WLAN card>/<FLAV>); LAYOUT comes from make_config.py:
#   EFIs/<macOS>/<WLAN>/<FLAV>/EFI          blank SMBIOS, safe to commit
#   EFIs/local/<macOS>/<WLAN>/<FLAV>/EFI    with Source/smbios.local.plist, gitignored -> copy to an ESP
# Inputs (OpenCore / kext / OcBinaryData zips) are NOT in this repo: they live in $RESOURCES
# (default ~/Projects/Hacktinosh/Resources, next to References/ and Tools/).
#
# usage: Scripts/build.sh [RELEASE|DEBUG ...]   (default: both; generates Source/smbios.local.plist on first run)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
RES="${RESOURCES:-$HOME/Projects/Hacktinosh/Resources}"
SRC="$ROOT/Source"
OUT="$ROOT/EFIs"
OC_VER="1.0.8"
MACSERIAL="${MACSERIAL:-$HOME/Projects/Hacktinosh/Tools/GenSMBIOS/Scripts/macserial}"
SMBIOS="$SRC/smbios.local.plist"
# bundle path inside the acidanthera zips (load order is set in make_config.py)
KEXTS=(Lilu.kext Kexts/VirtualSMC.kext Kexts/SMCProcessor.kext WhateverGreen.kext AppleALC.kext IntelMausi.kext NVMeFix.kext AirportBrcmFixup.kext BlueToolFixup.kext)
FLAVOURS=("${@:-RELEASE DEBUG}"); FLAVOURS=(${FLAVOURS[*]})
LAYOUT="$(python3 -I "$HERE/make_config.py" --layout)"   # e.g. 13/BCM943224PCIEBT2

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== common: OC Docs/ocvalidate, OcBinaryData, USBMap"
mkdir -p "$WORK/oc-rel" "$WORK/ocbin" "$WORK/usbmap"
unzip -q "$RES/OpenCore-$OC_VER-RELEASE.zip" 'Docs/*' 'Utilities/ocvalidate/*' -d "$WORK/oc-rel"
unzip -q "$RES/OcBinaryData-master.zip" -d "$WORK/ocbin"
OCBIN="$(find "$WORK/ocbin" -maxdepth 1 -mindepth 1 -type d | head -1)"
OCVALIDATE="$WORK/oc-rel/Utilities/ocvalidate/ocvalidate"
python3 -I "$HERE/make_usbmap.py" "$WORK/usbmap"
xattr -dr com.apple.quarantine "$WORK" 2>/dev/null || true

[ -f "$SMBIOS" ] || { echo "== SMBIOS (first run)"; python3 -I "$HERE/gen_smbios.py" "$MACSERIAL" "$SMBIOS"; }

assemble() {  # $1 = flavour, $2 = dest dir, $3 = smbios plist or ""
  local flav="$1" dest="$2" smb="$3" oc="$WORK/oc-$1/X64/EFI" kx="$WORK/kexts-$1"
  rm -rf "$dest/EFI"
  mkdir -p "$dest/EFI/BOOT" "$dest/EFI/OC"/{ACPI,Drivers,Kexts,Tools,Resources}
  cp "$oc/BOOT/BOOTx64.efi" "$dest/EFI/BOOT/"
  cp "$oc/OC/OpenCore.efi" "$dest/EFI/OC/"
  for d in OpenHfsPlus OpenRuntime OpenCanopy ResetNvramEntry AudioDxe; do cp "$oc/OC/Drivers/$d.efi" "$dest/EFI/OC/Drivers/"; done
  cp "$oc/OC/Tools/OpenShell.efi" "$dest/EFI/OC/Tools/"
  for s in SSDT-PLUG SSDT-EC SSDT-USBX; do cp "$SRC/SSDT dump/$s.aml" "$dest/EFI/OC/ACPI/"; done
  cp "$SRC/ACPI/"*.aml "$dest/EFI/OC/ACPI/"   # hand-made SSDTs (not from SSDTTime)
  cp -R "$kx/"*.kext "$WORK/usbmap/USBMap.kext" "$dest/EFI/OC/Kexts/"
  # OpenCanopy assets from OcBinaryData; Audio = only the 16-bit wav chime (no mp3s, see make_config.py)
  cp -R "$OCBIN/Resources/"{Font,Image,Label} "$dest/EFI/OC/Resources/"
  cp -R "$SRC/Resources/Audio" "$dest/EFI/OC/Resources/"
  python3 -I "$HERE/make_config.py" "$WORK/oc-rel/Docs/Sample.plist" "$dest/EFI/OC/config.plist" \
      "$(echo "$flav" | tr A-Z a-z)" ${smb:+"$smb"}
  find "$dest" -name .DS_Store -delete
  "$OCVALIDATE" "$dest/EFI/OC/config.plist" | grep -E 'issue|Completed'
}

for flav in "${FLAVOURS[@]}"; do
  echo "== $flav: OpenCore $OC_VER + kexts"
  mkdir -p "$WORK/oc-$flav" "$WORK/kz-$flav" "$WORK/kexts-$flav"
  unzip -q "$RES/OpenCore-$OC_VER-$flav.zip" 'X64/*' -d "$WORK/oc-$flav"
  for z in "$RES/kexts/"*-"$flav".zip; do unzip -q -o "$z" -d "$WORK/kz-$flav"; done
  for k in "${KEXTS[@]}"; do
    [ -d "$WORK/kz-$flav/$k" ] || { echo "missing $k in $RES/kexts/*-$flav.zip" >&2; exit 1; }
    cp -R "$WORK/kz-$flav/$k" "$WORK/kexts-$flav/"
  done
  # AirportBrcmFixup README: "You have to block (or remove) AirPortBrcm4360_Injector.kext in 11+".
  # Catalina is native and Big Sur+ only uses AirPortBrcmNIC_Injector -> remove the 4360 one.
  rm -rf "$WORK/kexts-$flav/AirportBrcmFixup.kext/Contents/PlugIns/AirPortBrcm4360_Injector.kext"
  assemble "$flav" "$OUT/$LAYOUT/$flav" ""
  assemble "$flav" "$OUT/local/$LAYOUT/$flav" "$SMBIOS"
done

echo "== done: EFIs/local/$LAYOUT/<FLAV>/EFI -> ESP"
