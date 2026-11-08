# HP ProDesk 600 G3 DM — Hackintosh Status

> ## 🛑 Known issue: sleep is broken
> Waking from sleep with a **DisplayPort monitor attached** hard-freezes the machine: power LED steady, black screen, no network, hard reset needed. **Run `sudo pmset -a sleep 0`** (display sleep keeps working) and don't use  → Sleep or a short press of the power button. Unresolved — see [Sleep](#sleep-unresolved) below.

## Hardware

| Component | Detail |
|---|---|
| CPU | Intel **i5-7500T** (Kaby Lake desktop, 35 W) |
| iGPU | Intel **HD Graphics 630** `8086:5912`, `AAPL,ig-platform-id` `0x59120000`; two DisplayPort outputs |
| PCH | **Q270** |
| Ethernet | Intel **I219-LM** `8086:15e3` (IntelMausi) |
| WLAN | **Apple BCM943224PCIEBT2** — PCIe Wi-Fi BCM43224 `14e4:4353` + USB Bluetooth (Apple VID `05ac`). **The EFIs below are tied to this card.** |
| Storage | Intel **Optane M10** 16 GB `8086:2522` + 500 GB SATA HDD, used as a Fusion Drive |
| Audio | Conexant **CX20632** (AppleALC `layout-id` 20), incl. boot chime |
| SMBIOS | `iMac18,1` |

Linux probe dump (lspci/lsusb/dmesg/ACPI) in [`Source/hack-linux-dump-20260928-1709/`](Source/hack-linux-dump-20260928-1709/).

## Which EFI

Layered as `EFIs/<macOS>/<WLAN card>/<flavour>/EFI`, same as the EliteBook tree:

| EFI | For |
|---|---|
| [`EFIs/13/BCM943224PCIEBT2/RELEASE/EFI`](EFIs/13/BCM943224PCIEBT2/RELEASE/EFI) | **Ventura 13**, daily use |
| [`EFIs/13/BCM943224PCIEBT2/DEBUG/EFI`](EFIs/13/BCM943224PCIEBT2/DEBUG/EFI) | Ventura 13, troubleshooting (`-v`, DEBUG OpenCore/kexts, OC log file) |

- **SMBIOS is blank** in these committed configs. `Scripts/build.sh` generates your own (`Source/smbios.local.plist`, gitignored) and writes ready-to-copy EFIs to `EFIs/local/…` (gitignored too). Its inputs, the pinned OpenCore/kext/OcBinaryData zips, are deliberately not in this repo: it reads them from `$RESOURCES` (default `~/Projects/Hacktinosh/Resources`). Pinned versions, downloaded from the official acidanthera releases: OpenCore 1.0.8 (DEBUG + RELEASE), OcBinaryData master, Lilu 1.7.2, VirtualSMC 1.3.8, WhateverGreen 1.7.1, AppleALC 1.9.8, IntelMausi 1.0.8, NVMeFix 1.1.3, AirportBrcmFixup 2.2.1, BrcmPatchRAM 2.7.2 (for BlueToolFixup).
- **Different WLAN card?** Every entry that only exists for the BCM943224PCIEBT2 has a `Comment` starting with `[WLAN]`, and each `config.plist` lists them under its `#Hardware` key (a comment key; OpenCore ignores it). Remove or replace those entries for your card.
- The same config is also built to boot **Catalina 10.15** (Ventura-only bits are gated by `MinKernel`). The sleep work (Iter 13–14) was only tested on Ventura.

## Status on Ventura 13.6.7

- ✅ iGPU acceleration, both DP outputs, DP hot-plug
- ✅ Wi-Fi + Bluetooth (BCM943224PCIEBT2)
- ✅ Ethernet, USB (custom 15-port map), audio + boot chime
- ✅ Fusion Drive (Optane M10 + HDD)
- ✅ Display sleep (`pmset displaysleep`)
- ❌ **System sleep**, see below
- 🟡 Intermittent kernel panic at sleep *entry* on the Optane M10 (`IONVMe ... Command timeout`), 2 of ~8 attempts. Doesn't matter while sleep is disabled.

## Sleep (unresolved)

The rule, confirmed with clean-boot tests:

| DP at sleep entry | DP at wake | Result |
|---|---|---|
| attached | attached | ❌ hard freeze (sometimes a reset ~30 s later) |
| attached | unplugged while asleep | ✅ wakes; re-plugging DP lights the screen |
| not attached | plugged in while asleep | ✅ wakes and lights the screen |
| not attached | not attached | ✅ wakes; plugging DP in afterwards works |

So the macOS framebuffer driver freezes when it has to **restore a display that was lit at sleep entry**. Lighting a freshly hot-plugged display after wake works. Linux S3 on the same box and monitor resumes fine, so firmware, hardware and the monitor are not the cause.

Tried with no effect: `forceRenderStandby=0`, `disable-agdc` (alone), the other DP port, `ig-platform-id 0x59160000`, `panic_on_display_hang=1 panic_on_gpu_hang=1` (no panic report). `force-online` was removed because it broke post-wake hot-plug. Fixed along the way: instant wake via XDCI (`SSDT-GPRW` + `GPRW→XPRW`). Also, a USB boot stick left plugged in causes instant wakes (XHC), so eject and unplug it after boot. Next untried step: kernel serial output over Intel AMT Serial-over-LAN, which needs AMT/MEBx access. Each attempt and its evidence is documented inline in [`Scripts/make_config.py`](Scripts/make_config.py).

## Repository layout

```
HP-ProDesk-600-G3/
├── README.md                    ← this file
├── EFIs/
│   ├── 13/BCM943224PCIEBT2/     ← committed EFIs (blank SMBIOS) + README for downloaders
│   │   ├── DEBUG/EFI/
│   │   └── RELEASE/EFI/
│   └── local/                   ← your EFIs with SMBIOS (gitignored)
├── Source/                      ← hand-made SSDTs, SSDTTime dump, chime audio, Linux dump
└── Scripts/                     ← build.sh + make_config.py (config generator, every choice commented),
                                   sleep-diagnose.sh, wifi-bt-diagnose.sh
```
