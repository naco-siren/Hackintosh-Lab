# Ventura 13.x EFI — uses 12/ as-is

This directory is intentionally empty apart from this README.

For HP EliteBook 840 G5 + BCM94352Z + macOS Ventura 13.x, **use the same EFI as Monterey**:

→ [`../12/BCM94352z/RELEASE/EFI/`](../12/BCM94352z/RELEASE/EFI/) — production
→ [`../12/BCM94352z/DEBUG/EFI/`](../12/BCM94352z/DEBUG/EFI/) — development with verbose logging

## Why a single EFI for two macOS versions

The Iter 11 recipe for native Bluetooth on Monterey/Ventura is:

- Strip the entire BrcmPatchRAM3 family (`BrcmPatchRAM3.kext`, `BrcmBluetoothInjector.kext`, `BrcmFirmwareData.kext` — all gated `MaxKernel=20.99.99`, i.e. Big Sur only)
- Replace stock BlueToolFixup with [CommandMaker's fork](https://github.com/CommandMaker/BrcmPatchRAM) at `MinKernel=21.0.0` (Monterey and later)
- Boot-args: `-btlfxallowanyaddr -btlfxchipsetdetection -btlfxboardid`
- NVRAM under `4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102`: `btlfx-product-name = "BCM20702A0"`

The `MinKernel`/`MaxKernel` gating already covers Darwin 21 (Monterey) through Darwin 22 (Ventura) identically. WiFi via `AirportBrcmFixup` + `brcmfx-driver=2` boot-arg is also unchanged across the Monterey/Ventura range. Verified by booting the Ventura 13.x installer from `12/BCM94352z/RELEASE` directly: install completed cleanly with no Ventura-specific tweaks, native BT functional from first boot (Vendor `0x004C` Apple, Chipset `BCM_20702A3`, factory firmware `v14 c4096`), AirDrop receive works.

## When this stops being true

The recipe breaks at the **Ventura → Sonoma** boundary (Darwin 23.0.0): Apple removes the stock BCM4352 driver path and replaces `IO80211Family` with `IOSkywalkFamily`. Sonoma+ requires injecting `IO80211FamilyLegacy.kext` + `IOSkywalkFamily.kext` plus a Skywalk Block-downgrade entry — deliberately NOT included in this Monterey/Ventura build. See top-level [`README.md`](../../README.md) "BT card decision matrix" path C/D for the long-term plan.

## On-target deploy

Same as for Monterey: mount the Ventura ESP, copy `12/BCM94352z/RELEASE/EFI/OC/` to `/Volumes/EFI/EFI/OC/`. Don't forget to inject your local SMBIOS values (the four scrubbed `PlatformInfo > Generic` fields — see top-level README) before first boot.
