# HP EliteBook 840 G5 — Hackintosh Status

## Hardware

| Component | Detail |
|---|---|
| CPU | Intel **i5-8350U** (Kaby Lake-R, Q1'18) |
| iGPU | Intel **UHD Graphics 620** — native `0x5917`, spoofed to `0x5916` |
| PCH | **Sunrise Point-LP** / 100-series mobile (`8086:9d4e`) — *not* 300-series Cannon Point |
| Memory | DDR4 |
| Display | eDP + HDMI 2.0 with LSPCON + USB-C DP alt-mode |
| WLAN | **Broadcom BCM94352Z** M.2 (PCIe BCM4352 `14e4:43b1` + USB BCM20702A1 BT `0489:e07a`, Foxconn rebrand) — replaced OEM Intel 8265 |
| Touchpad | I2C **Synaptics SYNA2393** at `\_SB.PCI0.I2C0.TPD0` |
| Pointing nub | PS/2 TrackPoint |
| Keyboard | PS/2 |
| Thunderbolt | TB3 (Alpine Ridge LP) — set to **Native + Low Power** in BIOS |

ACPI ground truth in [`SOURCE-OF-TRUTH/`](SOURCE-OF-TRUTH/) (two SSDTTime captures + Linux probe dumps with each WLAN card).

## SMBIOS

`MacBookPro15,4` (board-id `Mac-1E7E29AD0135F9BC`). 2019 13" MBP. Best community match for KBL-R + UHD 620 + the LSPCON HDMI path.

## macOS version status

| Version | Status | Notes |
|---|---|---|
| **11 Big Sur** (11.7.10) | ✅ **Working baseline** | Full WiFi/BT/AirDrop/Handoff. BT chipset reports as `BCM_20702A3` (post-firmware-injected, *not* `THIRD_PARTY_DONGLE`). Open issues: trackpad smoothness + sleep/wake. EFI in [`11/BCM94352z/EFI/`](11/BCM94352z/EFI/) |
| 12 Monterey | ⏳ Not attempted | Drop-in expected from Big Sur per [research](RESEARCH/per-version-playbook.md). Possible BT 240s IOKit stall risk |
| 13 Ventura | ⚠️ Partial in past tests | Reached userland but `kernelmanagerd stall(N, 240s): BCM20702A0` on this exact card |
| 14 Sonoma | ⚠️ Partial in past tests | Same BT stall (after iGPU AGDP fix). Would need `-btlfxboardid` (this flag is `>= Sonoma` only) |
| 15 Sequoia | ⚠️ Partial in past tests | Same BT stall + iGPU drama |
| 16 Tahoe | ❌ Dead path | Apple removed BCM4352 from `0xFireWolf/AppleBCMWLANCompanion`. Tahoe panics on BlueToolFixup family. Apple Silicon-only push |

## BT card decision matrix

The BCM20702A1 firmware injection (BrcmPatchRAM3) causes a kernel-level `kernelmanagerd stall(N, 240s)` on macOS Monterey+ for this hardware — undocumented elsewhere as of 2026-04. CommandMaker's [Feb 2026 fork](https://github.com/CommandMaker/BrcmPatchRAM) addresses BT identification (`THIRD_PARTY_DONGLE`) but **not** the IOKit USB termination stall we hit. Path forward:

| Path | BCM full functionality | Maintenance | Recommended for |
|---|---|---|---|
| **A. Stay on Big Sur** | ✅ Full WiFi/BT/AirDrop | Low (EOL OS, no security updates since 2023-09) | **Daily driver if you can live without security updates** |
| B. Upgrade to Monterey, keep BCM | ❓ BT may still stall (untested) | Medium | Cheap experiment if curious |
| C. Upgrade to Sonoma/Sequoia, keep BCM | ❌ BT stall confirmed | High (refight per dot-release) | Skip |
| **D. Replace BCM94352Z with Fenvi BCM94360NG** | ✅ Native VID/PID, no firmware-inject dance | Low (one-time hardware swap, ~¥150-300) | **Real upgrade path to Sonoma/Sequoia** |
| E. Revert to Intel 8265, BT via dongle | ⚠️ WiFi via itlwm (user-space) | Medium (itlwm per-update) | Community-validated alternative; every other 840 G5 hackintosh repo does this |
| F. ACPI-mask BCM BT USB port + external dongle | WiFi BCM ✅, BT external | Medium (write SSDT-DISABLE-BT) | Middle path if you want internal WiFi but accept external BT |

Default plan: Live on Big Sur for now; revisit when ready for path D (hardware swap).

## Repository layout

```
HP-Elitebook-840-G5/
├── README.md                      ← this file
├── TESTING-PLAN.md                ← iterative test matrix (live, updated each iter)
├── 11/                            ← Big Sur (Darwin 20)
│   └── BCM94352z/EFI/            ← tested baseline with BCM card
├── [12/BCM94352z/EFI/]            ← future Monterey baseline
├── [14/BCM94352z/EFI/]            ← future Sonoma baseline
├── WIP/EFI/                       ← active development tree
└── SOURCE-OF-TRUTH/               ← DSDT/SSDT + Linux probe dumps
    ├── 1st time/SSDTTime-Results/
    ├── 1st time/hack-linux-dump-...-Intel8265NGW/
    ├── 1st time/hack-linux-dump-...-BCM94352z/
    └── 2nd time/                  ← redundant capture
```

## Confirmed working in Big Sur 11.7.10

- ✅ Boot to GUI in ~3 minutes from SSD
- ✅ iGPU framebuffer, full Metal acceleration
- ✅ I2C Synaptics trackpad with 5-finger gestures (smoothness suboptimal — see TESTING-PLAN)
- ✅ TrackPoint nub
- ✅ Internal keyboard (basic keys; HP Fn keys not yet remapped)
- ✅ Internal display backlight
- ✅ HDMI 2.0 external out (LSPCON)
- ✅ USB-C DisplayPort alt-mode (dual external display via TB3 dock confirmed)
- ✅ Audio internal speakers
- ✅ Ethernet (IntelMausi)
- ✅ **Wi-Fi BCM4352** (native via AirportBrcmFixup-patched stock AirportBrcmNIC.kext)
- ✅ **Bluetooth BCM20702A1** — Apple recognizes as native `BCM_20702A3`, fw v14 c5747
- ✅ **AirDrop both directions** (verified by AirDropping `bluetooth.txt` from Hack to Mac)
- ✅ Handoff supported, Instant Hot Spot supported
- ✅ **Sleep/wake** (Iter 8 GOLDEN baseline): lid-close enters S3, power LED breathes, lid-open wakes. Apple-menu Sleep also works. **Cold-boot tested**.

## Sleep — how it actually works

The working sleep configuration depends on **two layers**:

**EFI side** (in `11/BCM94352z/EFI/`, captured in commit `73fa2e7`):
- boot-args: `-igfxblr` (LSPCON backlight register preservation) + `hbfx-ahbm=1` (HibernationFixup pure-S3 mode)
- iGPU DeviceProperty: `enable-backlight-registers-fix = 01000000` (companion to `-igfxblr`)
- `agdpmod=pikera` (AGDP iGPU policy bypass)
- `darkwake=0` (legacy boot-arg, mostly cosmetic on Big Sur but doesn't hurt)
- `SSDT-DISABLE-FP.aml` is on disk but `Enabled=false` in config — kept as a spare; enabling it cascades and breaks BCM BT enumeration timing (see Iter 6/7 in TESTING-PLAN)

**macOS user-space side** (in `/Library/Preferences/SystemConfiguration/com.apple.PowerManagement.plist`):
- These settings were applied by [`diagnostic-scripts/sleep-diagnose.sh`](diagnostic-scripts/sleep-diagnose.sh) STEP 2 across iterations 4–7 and are now persistent:
  ```
  womp 0           tcpkeepalive 0          networkoversleep 0
  powernap 0       hibernatemode 0         standby 0
  autopoweroff 0   proximitywake 0         sleepservicestimeout 1
  ```
- Key ones: **`proximitywake 0`** (kills BT-Continuity wake path) and **`sleepservicestimeout 1`** (shrinks Sleep Services window to 1s) — these silenced the "11–12s periodic XDCI wake" originally misattributed to the Validity fingerprint reader.

**If you ever reinstall macOS** (or somehow lose these plist settings): just re-run `bash diagnostic-scripts/sleep-diagnose.sh` and respond ENTER through the prompts; STEP 2 re-applies the settings. NVRAM reset via OpenCore picker does NOT lose these (they're in `/Library/Preferences/`, not NVRAM).

## Currently open

- 🟡 **Trackpad smoothness** — surface works + 2-finger scroll works, but pointer movement is jittery vs Linux/G3-PS2; 4/5-finger gestures unreliable. Iter 1–4 driver swaps (2.9.1, baseline, PS/2 path) all felt the same — stock macOS `AppleIntelLpssI2C` may be the actual driver chain regardless. **Active work** — see [TESTING-PLAN.md](TESTING-PLAN.md) "Trackpad — next round" for pending T3 (VoodooI2CHID), T4 (VoodooRMI), and user-space `defaults` tweaks not yet tried.

- 🟡 Thunderbolt 3 partial: hot-plug + DP alt-mode work, but TB-tunneled devices (USB hub / I219 / audio in dock) not enumerated. **Expected** for non-Apple TB controllers — accept as-is unless you swap to a real Apple-T2 host.

- 🟡 HP Fn keys: F-row special keys not yet bound (volume / brightness / display etc.). Reference [`Hackintosh-HP-Elitebook-840-G5-Sonoma`](../Hackintosh-HP-Elitebook-840-G5-Sonoma/) has an `SSDT-INPUT.aml` for this — backlog item.

## Iteration history index

Living narrative across iterations is in [TESTING-PLAN.md](TESTING-PLAN.md). Per-iteration commit messages have the deepest debugging notes:

- *(latest)* Sleep stabilization landing — GOLDEN promoted as baseline + Iter 6/7/8 narrative (squashed). Final fix is the EFI changes from Iter 4 plus persistent macOS pmset settings; the SSDT-DISABLE-FP attempt was a false positive. See README "Sleep — how it actually works" + the commit body for the lesson narrative.
- `4bb39fa` Iter 4: accept trackpad limit, retest sleep on battery (sleep tracing converges on Dark Wake stuck pattern)
- `bc20026` Diagnostic scripts (sleep + trackpad)
- `14fe3e5` Iter 3: PS/2 trackpad path + sleep diagnostic ask
- `f899835` Iter 2: revert trackpad to 2.8 baseline + correct sleep recipe
- `84f48f1` Iter 1: VoodooI2C 2.9.1 + iGPU sleep boot-args
- `37d130a` Doc: testing plan + Big Sur baseline overview
- `4aa5f3b` Big Sur baseline EFI (originally what installed Big Sur)
- `0aef885` Reorganize per-(macOS × WLAN-hardware) layout
- `1270daf` Add SOURCE-OF-TRUTH dumps (DSDT + Linux probes)
- `15a69f0` Linux dump script
- `431e0d0` Touchpad fix (XOSI rename + SYNA2393 match)

## Research artifacts

Background research subagent outputs (per-version Hackintosh playbook for Monterey/Sonoma/Sequoia, BCM94352Z BT 240s-stall deep-dive) are summarized in earlier conversation threads — TODO archive into [`RESEARCH/`](RESEARCH/) when revisiting newer macOS versions.
