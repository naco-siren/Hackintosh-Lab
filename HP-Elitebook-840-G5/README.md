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
| Touchpad | I2C HID **Synaptics SYNA3071** at `\_SB.PCI0.I2C0.TPD0` (DSDT name TPD0; runtime IOReg name SYNA3071, `_CID = "PNP0C50"`, GPIO pin 82, 400 kHz). The README originally claimed SYNA2393 — that was wrong; the actual enumerated `IOName` is SYNA3071, which is why `VoodooI2CSynaptics` (Iter 1–8) never bound and `VoodooI2CHID` is the right driver (Iter 9) |
| Pointing nub | PS/2 TrackPoint |
| Keyboard | PS/2 |
| Thunderbolt | TB3 (Alpine Ridge LP) — set to **Native + Low Power** in BIOS |

ACPI ground truth in [`SOURCE-OF-TRUTH/`](SOURCE-OF-TRUTH/) (two SSDTTime captures + Linux probe dumps with each WLAN card).

## SMBIOS

`MacBookPro15,4` (board-id `Mac-1E7E29AD0135F9BC`). 2019 13" MBP. Best community match for KBL-R + UHD 620 + the LSPCON HDMI path.

## macOS version status

| Version | Status | Notes |
|---|---|---|
| **11 Big Sur** (11.7.10) | ✅ Working | Full WiFi/BT/AirDrop/Handoff via the classic BrcmPatchRAM firmware-injection path (Iter 8 GOLDEN). Sleep solved Iter 8, trackpad Iter 9 (I2C HID swap). EFI: [`EFIs/11/BCM94352z/EFI/`](EFIs/11/BCM94352z/EFI/). EOL — no security updates since 2023-09. |
| **12 Monterey** | ✅ **Working** (Iter 11) | Native BT — `bluetoothd` identifies the BCM20702A1 as Apple-internal (Vendor `0x004C`, Chipset `BCM_20702A3`, factory firmware `v14 c4096`) — via CommandMaker BlueToolFixup fork + cutting the entire `BrcmPatchRAM3 / BrcmBluetoothInjector / BrcmFirmwareData` trio with `MaxKernel=20.99.99`. EFI: [`EFIs/12/BCM94352z/{DEBUG,RELEASE}/EFI/`](EFIs/12/BCM94352z/). |
| **13 Ventura** | ✅ **Working via 12/ EFI** (verified Iter 11) | Same EFI as Monterey loads unchanged on Ventura — kernel-version gating (`MinKernel=21.0.0` on the fork BlueToolFixup, `MaxKernel=20.99.99` on the BrcmPatchRAM trio) covers Darwin 21–22 identically. See [`EFIs/13/README.md`](EFIs/13/README.md). Currently receiving Apple security updates. |
| 14 Sonoma | ⚠️ Intentionally skipped | Apple removes stock BCM4352 driver and replaces IO80211Family with IOSkywalkFamily. Workable via injecting `IO80211FamilyLegacy.kext` + `IOSkywalkFamily.kext` + a Skywalk Block-downgrade entry, but per-dot-release maintenance burden. User chose Ventura as the daily-driver plateau. |
| 15 Sequoia | ⚠️ Intentionally skipped | Same Skywalk transition as Sonoma + further Apple Intel-Mac feature regressions (UI fluidity, app compatibility). Not pursued. |
| 16 Tahoe | ❌ Dead path | Apple removed BCM4352 from `0xFireWolf/AppleBCMWLANCompanion`; Tahoe panics on the BlueToolFixup family. Apple Silicon-only push. |

## BT card decision matrix

The BCM20702A1 firmware injection (BrcmPatchRAM3) causes a kernel-level `kernelmanagerd stall(N, 240s)` on macOS Monterey+ for this hardware. Big Sur tolerates the IOKit USB termination grace period (~5s); Monterey+ enforces a 240s window that — beyond just slowing boot — leaves `bluetoothd` and `diskarbitrationd` with degraded IOKit notification ports (BT permanently spinning, USB hot-plug invisible to Disk Utility). Iter 11 found that **on Monterey/Ventura you don't need to fix the stall — you skip it entirely**: BCM20702A1's factory firmware (`v14 c4096`) is already supported by Monterey+ stock CoreBluetooth; you only need [CommandMaker's BlueToolFixup fork](https://github.com/CommandMaker/BrcmPatchRAM) to teach `bluetoothd` to recognise the card as native (instead of `THIRD_PARTY_DONGLE`). So the working recipe per macOS:

- **Big Sur**: BrcmPatchRAM3 family enabled (stock Big Sur CoreBluetooth needs the `c5747` firmware injection).
- **Monterey/Ventura**: BrcmPatchRAM3 family `MaxKernel=20.99.99` (skipped) + BlueToolFixup fork `MinKernel=21.0.0` (loaded) + `-btlfx*` boot-args + `btlfx-product-name=BCM20702A0` NVRAM. The Iter 11 commit body has the full reasoning chain.

Both recipes ship in the same EFI thanks to MinKernel/MaxKernel gating; OpenCore picks the right one per-boot. With that understood, the long-term path matrix:

| Path | BCM full functionality | Maintenance | Recommended for |
|---|---|---|---|
| A. Stay on Big Sur | ✅ Full WiFi/BT/AirDrop | Low (EOL OS, no security updates since 2023-09) | Daily driver if you don't care about security updates |
| **B. Monterey or Ventura, keep BCM** | ✅ Native BT (Iter 11 recipe) | Low (config delta vs Big Sur is small and frozen) | **Daily driver — the new sweet spot. Security updates current, all hardware features work.** |
| C. Sonoma / Sequoia, keep BCM | ⚠️ Workable via IO80211FamilyLegacy + IOSkywalkFamily injections | High (refight per dot-release as Apple changes Skywalk internals) | Skip unless committed to per-release maintenance |
| **D. Replace BCM94352Z with Fenvi BCM94360NG** | ✅ Native Apple VID/PID, no firmware-inject dance | Low (one-time hardware swap, ~¥150-300) | **Real upgrade path to Sonoma+ when Ventura's security support ends** |
| E. Revert to Intel 8265, BT via dongle | ⚠️ WiFi via itlwm (user-space) | Medium (itlwm per macOS update) | Community-validated alternative; every other 840 G5 hackintosh repo does this |
| F. ACPI-mask BCM BT USB port + external dongle | WiFi BCM ✅, BT external | Medium (write SSDT-DISABLE-BT) | Middle path if you want internal WiFi but accept external BT |

**Default plan (post Iter 11)**: Ventura on path B is the daily-driver plateau — Apple security updates current, native BT, all hardware functional, no firmware-injection cascade. Path D is the upgrade plan if/when Ventura's security support ends and Sonoma+ becomes necessary.

## Repository layout

```
HP-Elitebook-840-G5/
├── README.md                       ← this file
├── EFIs/                           ← all per-(macOS × WLAN-card) EFI variants
│   ├── 11/BCM94352z/EFI/          ← Big Sur (Iter 8 GOLDEN; daily-driver-grade)
│   ├── 12/BCM94352z/
│   │   ├── DEBUG/EFI/             ← Monterey/Ventura with -v debug=0x100 (dev)
│   │   └── RELEASE/EFI/           ← Monterey/Ventura production (Iter 11)
│   ├── 13/README.md               ← pointer: Ventura uses 12/ EFI as-is
│   ├── BlueToolFixup.kext.zip     ← CommandMaker fork source, archived for traceability
│   └── WIP/EFI/                   ← dev scratchpad, mirror of latest working state
├── Scripts/                        ← diagnostic + setup helpers
│   ├── README.md                  ← how to run + what each one does
│   ├── TESTING-PLAN.md            ← iteration log (Iter 1–9 archive; Iter 10–11 in commit messages)
│   ├── sleep-diagnose.sh          ← guided sleep test, applies pmset settings
│   ├── trackpad-diagnose.sh       ← one-shot IOReg/kextstat/log dump
│   ├── apply-trackpad-prefs.sh    ← user-space trackpad defaults (post-reinstall)
│   └── convert-audio-mp3-to-wav.sh ← chime-fix helper for 16-bit codecs (Iter 10)
└── SOURCE-OF-TRUTH/                ← DSDT/SSDT + Linux probe dumps
    ├── 1st time/SSDTTime-Results/
    ├── 1st time/hack-linux-dump-...-Intel8265NGW/
    ├── 1st time/hack-linux-dump-...-BCM94352z/
    └── 2nd time/                  ← redundant capture
```

## Confirmed working in Big Sur 11.7.10

- ✅ Boot to GUI in ~3 minutes from SSD
- ✅ iGPU framebuffer, full Metal acceleration
- ✅ I2C HID Synaptics trackpad — full multi-finger gestures, smoothness on par with Linux/Win10 reference (Iter 9 fix)
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

## Trackpad — how it actually works

The G5's touchpad is dual-bus capable: it enumerates *both* on the I2C0 controller (as `SYNA3071`, `compatible = PNP0C50`, GPIO IRQ pin 82) *and* via PS/2 Synaptics InterTouch on the i8042 controller. Whichever bus has a matched driver claims the device first; the other side stays inert. **Iter 1–8 had no driver matching on the I2C side** (`VoodooI2CSynaptics` looks for SYNA2393 IOName, didn't match SYNA3071; `VoodooI2CHID` was disabled in config), so the touchpad fell to PS/2 InterTouch via `VoodooPS2Trackpad` → `ApplePS2SynapticsTouchPad`.

PS/2 InterTouch caps multi-touch sample rate at ~80–100 Hz with serialised per-finger packets. Fast 2-finger flings emit too few intermediate samples for `AppleMultitouchTrackpadHIDEventDriver` to detect movement, so they're misclassified as 2-finger taps. This was the user-visible symptom that made Iter 1–4 feel "the same regardless of which I2C kext we swapped" — none of those swaps changed the bus.

**Iter 9 fix**: enable `VoodooI2CHID` (matches `_CID = PNP0C50` → claims the I2C SYNA3071), disable `VoodooPS2Trackpad` (avoid double-binding on PS/2 side), disable `VoodooI2CSynaptics` (was never matching anyway, removed entirely from EFI). The TrackPoint nub keeps working because it lives on a separate PS/2 mouse channel served by `VoodooPS2Mouse` — verified in trackpad-diagnose IOReg as a distinct `IOHIDInterface` with `Product = "Mouse"`, `Transport = "PS2"`, independent of the touchpad.

Post-Iter-9 driver chain: `I2C0 PCI → VoodooI2CControllerDriver → SYNA3071 → VoodooI2CHIDDevice (Transport=I2C, GPIO interrupt) → VoodooInput (Magic Trackpad emulation) → IOHIDInterface → AppleMultitouchTrackpadHIDEventDriver`.

User-space prefs applied alongside (orthogonal to driver fix, but worth keeping): `defaults write -g com.apple.trackpad.scaling -float 3.0`, plus 3-finger drag and lower click thresholds. See [`Scripts/apply-trackpad-prefs.sh`](Scripts/apply-trackpad-prefs.sh) if reapplying after a macOS reinstall.

## Sleep — how it actually works

The working sleep configuration depends on **two layers**:

**EFI side** (in `EFIs/11/BCM94352z/EFI/`, captured in commit `73fa2e7`):
- boot-args: `-igfxblr` (LSPCON backlight register preservation) + `hbfx-ahbm=1` (HibernationFixup pure-S3 mode)
- iGPU DeviceProperty: `enable-backlight-registers-fix = 01000000` (companion to `-igfxblr`)
- `agdpmod=pikera` (AGDP iGPU policy bypass)
- `darkwake=0` (legacy boot-arg, mostly cosmetic on Big Sur but doesn't hurt)
- `SSDT-DISABLE-FP.aml` is on disk but `Enabled=false` in config — kept as a spare; enabling it cascades and breaks BCM BT enumeration timing (see Iter 6/7 in [`Scripts/TESTING-PLAN.md`](Scripts/TESTING-PLAN.md))

**macOS user-space side** (in `/Library/Preferences/SystemConfiguration/com.apple.PowerManagement.plist`):
- These settings were applied by [`Scripts/sleep-diagnose.sh`](Scripts/sleep-diagnose.sh) STEP 2 across iterations 4–7 and are now persistent:
  ```
  womp 0           tcpkeepalive 0          networkoversleep 0
  powernap 0       hibernatemode 0         standby 0
  autopoweroff 0   proximitywake 0         sleepservicestimeout 1
  ```
- Key ones: **`proximitywake 0`** (kills BT-Continuity wake path) and **`sleepservicestimeout 1`** (shrinks Sleep Services window to 1s) — these silenced the "11–12s periodic XDCI wake" originally misattributed to the Validity fingerprint reader.

**If you ever reinstall macOS** (or somehow lose these plist settings): just re-run `bash Scripts/sleep-diagnose.sh` and respond ENTER through the prompts; STEP 2 re-applies the settings. NVRAM reset via OpenCore picker does NOT lose these (they're in `/Library/Preferences/`, not NVRAM).

## Currently open (accepted-as-is)

- 🟡 **AirDrop discovery is intermittent post-wake on Monterey/Ventura**: sometimes white Mac sees Hackintosh but not vice versa, sometimes the reverse. Receiving and sending both work whenever the peer is visible; the flaky part is the discovery list. Two contributing factors:
  1. **Hackintosh IDS / Continuity entitlement gap**: `sharingd` fails to register `com.apple.private.alloy.nearby-idswake` (`Operation not permitted` — entitlement-gated, persistent across boots). The OP-suggested NVRAM fallback (`bluetoothInternalControllerInfo = 0000…` under either GUID) was tested and had no measurable effect.
  2. **2.4 GHz BLE-advertising interference / mDNSResponder cache**: the directional asymmetry can flip between sessions, which is more consistent with stochastic discovery noise (multiple Apple devices in the same room sharing the same advertising channel) than with a deterministic entitlement bug.
  
  Treated as accept-as-is: receiving AirDrops always works, sending works whenever the target appears, and the discovery flakiness is plausibly home-WiFi-environment-dependent rather than Hackintosh-deterministic.

- 🟡 **Wake from S3 takes ~8s** on Monterey/Ventura (`IGPU` / `HDEF` / `TXHC` / `pci-bridge` / `EP02` each at 4.0s `SetState` delay). PCIe root-complex D3→D0 link training latency on KBL-LP — confirmed not boot-arg-gateable (Iter 11 darkwake=0 removal had zero measurable effect). Hardware floor.

- 🟡 **AC sleep entry slower than BATT**: Monterey/Ventura's AC dark-wake budget is wider than Big Sur's, so on AC the system bumps through dark-wake-linger cycles before progressing to S3 (5+ min vs <30s on battery). By macOS design, not an EFI bug. Existing pmset settings push it as aggressive as is reasonable.

- 🟡 **Thunderbolt 3 partial**: hot-plug + DP alt-mode work, but TB-tunneled devices (USB hub / I219 / audio in dock) not enumerated. Expected for non-Apple TB controllers — accept as-is. Ventura System Information surfaces two "ExpressCard" entries (`8086:15d9` Alpine Ridge NHI + `8086:15db` Alpine Ridge integrated XHCI) with status-bar "Power off card" menu items; cosmetic mislabel only — **don't power them off, would disable TB3/USB-C**.

- 🟡 **HP Fn keys**: F-row special keys not yet bound (volume / brightness / display etc.). Reference [`Hackintosh-HP-Elitebook-840-G5-Sonoma`](../Hackintosh-HP-Elitebook-840-G5-Sonoma/) has an `SSDT-INPUT.aml` for this — backlog, not pursued.

## Iteration history index

Living narrative across iterations is in [`Scripts/TESTING-PLAN.md`](Scripts/TESTING-PLAN.md) (Iter 1–9 archive). Per-iteration commit messages from Iter 10 onward have the deepest debugging notes:

- *(latest)* **Iter 11** — Monterey & Ventura native Bluetooth, via CommandMaker fork BlueToolFixup + cutting BCM kexts on Monterey+. Counterintuitive discovery: `BrcmPatchRAM3` firmware injection is the SOURCE of the cascade damage (kernelmanagerd USB termination grace period eats 240s and leaves `bluetoothd` + `diskarbitrationd` notification ports broken), not a fix to be tuned. Stripping the BrcmPatchRAM trio on Monterey+ + the fork's chipset-detection patch on `bluetoothd` = native Apple-internal-controller identification (Vendor `0x004C`, factory firmware). Same EFI works on Ventura unchanged. See README "BT card decision matrix" + commit body.
- **Iter 10** — OpenCore 1.0.7 RELEASE/DEBUG split + boot chime via wav substitution. `EFIs/<macos>/<variant>/{DEBUG,RELEASE}/` per-build-type layout introduced. Boot chime debugging led to discovering Conexant CX8200 codec only supports 16/24-bit PCM but OC's mp3 decoder produces 32-bit float — `Scripts/convert-audio-mp3-to-wav.sh` pre-decodes to 16-bit wav as the fix. Repository layout reorganised.
- **Iter 9** — Trackpad smoothness resolved via I2C HID bus swap. Diagnose run on GOLDEN baseline showed the touchpad was actually being driven via PS/2 InterTouch the whole time (not stock `AppleIntelLpssI2C` as Iter 3 wrongly inferred). Switched to `VoodooI2CHID` claiming the I2C `SYNA3071` device, disabled `VoodooPS2Trackpad`. See README "Trackpad — how it actually works" + commit body.
- Sleep stabilization landing — GOLDEN promoted as baseline + Iter 6/7/8 narrative (squashed). Final fix is the EFI changes from Iter 4 plus persistent macOS pmset settings; the SSDT-DISABLE-FP attempt was a false positive. See README "Sleep — how it actually works" + the commit body for the lesson narrative.
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
