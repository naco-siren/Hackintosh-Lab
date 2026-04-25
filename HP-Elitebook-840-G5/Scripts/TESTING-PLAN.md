# Testing Plan — archive (Big Sur trackpad + sleep, both resolved)

> **Sleep is RESOLVED** in Iter 8 / commit `73fa2e7` (GOLDEN promoted to baseline). Cold-boot verified. Working state combines EFI changes (`-igfxblr` + `enable-backlight-registers-fix` + `hbfx-ahbm=1`) and macOS user-space pmset settings (in `/Library/Preferences/SystemConfiguration/`). Don't touch unless it breaks. See README "Sleep — how it actually works".

> **Trackpad is RESOLVED** in Iter 9 (this iteration). Driver chain swapped from PS/2 InterTouch (Iter 1–8 actual binding, misdiagnosed as stock I2C HID across Iter 3) to I2C HID via `VoodooI2CHID` claiming the SYNA3071 PNP0C50 device. See README "Trackpad — how it actually works" + Iter 9 commit body for the full hypothesis-revision narrative.

> **No active workstream.** This document is now archive of how we got here. Below: trackpad option-matrix that was used during Iter 9 planning, sleep option-matrix for reference, full iteration log Iter 1–9.

---

## Workflow per iteration (for future regression debugging)

sync `WIP/EFI/` from `11/BCM94352z/EFI/` → apply iteration changes → mount internal SSD ESP from running Big Sur → `cp -R WIP/EFI/* /Volumes/EFI/EFI/` → reboot → test → record results in **Iteration log** below → AI updates the next iteration based on outcomes. Trackpad-diagnose / sleep-diagnose scripts in `diagnostic-scripts/` capture state into AirDroppable text files.

## Open problems

### P1 — Trackpad smoothness 🟡
- 5-finger gestures *work*, but pointer movement/scrolling is jittery
- Reference: HP EliteBook 840 G3 (older, lower-spec) using **PS/2** path is silky-smooth on Sequoia
- Hypothesis: VoodooI2CSynaptics 2.8 bundled in EFI is from 2023; 2.9.1 (Dec 2024) is current

### P2 — Sleep/wake black screen 🔴
- Lid close → reopen → screen never lights back up
- Backlight registers don't survive iGPU's transition into D3
- Standard HP + LSPCON laptop symptom

---

## Trackpad option matrix (T)

| ID | Approach | Invasiveness | Risk | Notes |
|---|---|---|---|---|
| **T1** | Upgrade VoodooI2CSynaptics 2.8 → 2.9.1 | Low — drop-in binary swap | Low | Acidanthera VoodooI2C release Dec 2024 |
| **T2** | Switch to **VoodooRMI** (newer Synaptics universal) | High — replace kext + may need VoodooSMBus | Medium — VoodooRMI [#67](https://github.com/VoodooSMBus/VoodooRMI/issues/67) suggests SYNA2393 unconfirmed | Last resort if T1+T3 both fail |
| **T3** | Switch to **VoodooI2CHID** (generic HID path via `_CID = "PNP0C50"`) | Low — disable Synaptics, enable HID | Low | Loses Synaptics-specific gestures; often *smoother* sliding |
| T4 | Tune VoodooI2CSynaptics IOKitPersonalities params | Low — Info.plist edit | Medium — usually doesn't fix root smoothness | Skip unless desperate |

> **G5 cannot use VoodooPS2Trackpad** — touchpad is wired physically as I2C only. The G3's PS/2 path is hardware-different.

## Sleep option matrix (S)

| ID | Approach | Where | Notes |
|---|---|---|---|
| **S1** | boot-arg `igfxonln=1` | NVRAM > Add > boot-args | Forces iGPU framebuffer to stay online during transitions |
| **S2** | boot-arg `-igfxblr` | NVRAM > Add > boot-args | LSPCON laptops — preserves backlight registers across sleep |
| **S3** | DeviceProperty `enable-backlight-registers-fix=01000000` | DeviceProperties > `PciRoot(0x0)/Pci(0x2,0x0)` | **Companion to `-igfxblr`** — actually applies the fix |
| S4 | DeviceProperty `enable-backlight-smoother=01000000` | DeviceProperties > `PciRoot(0x0)/Pci(0x2,0x0)` | Smoother backlight transitions, peripheral |
| S5 | HibernationFixup boot-arg `hbfx-ahbm=1` | NVRAM > Add > boot-args | Auto-disable hibernate (force pure S3) |
| S6 | Custom SSDT for `_LID` ACPI method | new `SSDT-LIDFIX.aml` | Only if S1–S5 fail entirely |

For HP+LSPCON laptops, the standard recipe is **S1 + S2 + S3** as a trio.

---

## Iteration plan

Each iteration combines T-options with S-options into a single boot-test cycle.

### Iteration 1 — Best-bang-for-buck combined test

**Trackpad**: T1 (upgrade VoodooI2CSynaptics 2.8 → 2.9.1)
**Sleep**: S1 + S2 (boot-args only, no DeviceProperties touch yet)

Rationale: All three changes are low-risk, well-targeted at the most common root cause for each problem. Either both fix, neither, or one.

Concrete edits:
1. Replace `WIP/EFI/OC/Kexts/VoodooI2CSynaptics.kext` binary with 2.9.1 release (downloaded fresh from [acidanthera/VoodooI2C](https://github.com/acidanthera/VoodooI2C/releases))
2. Edit `WIP/EFI/OC/config.plist`:
   - Sync from `11/BCM94352z/EFI/OC/config.plist` first (drops residual diagnostic args)
   - boot-args: append ` igfxonln=1 -igfxblr`
3. plutil -lint to verify

Expected acceptance criteria:
- Trackpad: cursor movement noticeably smoother on 1-finger drag, 2-finger scroll less jittery
- Sleep: lid close, wait 30 sec, lid open → screen relights within 1-2 sec, system functional

### Iteration 2 — Branched on Iter 1 outcome

| Iter 1 outcome | Iter 2 action |
|---|---|
| ✅ Both fixed | Done. Promote `WIP/EFI/` to `11/BCM94352z/EFI/`. Skip Iter 2+ |
| ✅ Trackpad fixed, ❌ Sleep still broken | Add **S3** (DeviceProperty `enable-backlight-registers-fix`) on top of Iter 1 |
| ❌ Trackpad still jittery, ✅ Sleep fixed | Swap T1 → **T3** (try VoodooI2CHID) keeping S1+S2 |
| ❌ Both still broken | Add S3 + swap to T3 — both deeper changes simultaneously |

### Iteration 3 — Last-resort branches (only if Iter 2 partial)

- If trackpad still bad after T1+T3: try **T2** (VoodooRMI). Verify SYNA2393 match before committing.
- If sleep still bad after S1+S2+S3: add **S4 + S5** together. If that fails, the issue is ACPI `_LID` and we need **S6**: custom SSDT-LIDFIX (will require digging into DSDT.dsl `\_SB.LID0` or `\_SB.PCI0.LPCB.EC0.LID` to locate the real path).

---

## Iteration log

> Filled in by user feedback after each test boot. AI updates the next iteration accordingly.

### Iteration 9 — ✅ TRACKPAD RESOLVED via I2C HID bus swap (2026-04-25)

**Setup**: Iter 8 had landed sleep as GOLDEN baseline. Trackpad was annotated "accept Big Sur jitter as hardware/macOS limit" in Iter 4 / 8 narrative. User wanted to revisit because reference frame (G3 PS/2 on Sequoia, also Linux + Win10 on this same G5) proved the touchpad hardware was capable of silky-smooth multi-finger input. The Iter 4 acceptance was a wrong conclusion derived from a wrong diagnosis.

**Step 1 — re-run trackpad-diagnose.sh on GOLDEN baseline (output `~/Desktop/trackpad-diagnose-20260425-1557.txt`)**. Findings overturned multiple Iter-1-through-8 assumptions:

1. **`kextstat` showed `VoodooI2C 2.8` + `VoodooInput 1.1.3` loaded, but `VoodooI2CSynaptics` NOT loaded.** It had been "enabled in config" since Iter 4, but its `IOPropertyMatch` keys on `IOName=SYNA2393` and the actual ACPI device enumerates as `SYNA3071` (per IOReg lines 280–294). So the match never fired — across Iter 1–8 — and `kextstat` would have confirmed this if anyone had looked carefully at any earlier iteration. Iter 4's "re-enable VoodooI2CSynaptics" was a no-op.

2. **The touchpad enumerates on BOTH I2C0 *and* PS/2.** I2C0 side: `VoodooI2CControllerDriver` matched, `SYNA3071` device visible with `compatible = PNP0C50`, `gpioPin = 82`, but **no driver child** — nothing claimed the device on this bus because `VoodooI2CHID` was disabled in config (Iter 0 inheritance, never revisited) and `VoodooI2CSynaptics` had the wrong IOPropertyMatch. PS/2 side: `ApplePS2SynapticsTouchPad` (from `VoodooPS2Trackpad`) bound with `Intertouch Support = Yes` and full multi-finger reporting, with `VoodooInput` Magic-Trackpad-emulating it to userspace.

3. **The actual user-facing driver chain has been, since Iter 0**: `ACPI PS/2 → ApplePS2SynapticsTouchPad → VoodooInput → IOHIDInterface → AppleMultitouchTrackpadHIDEventDriver`. **Not** "stock `AppleIntelLpssI2C`" as Iter 3 inferred from kextstat — that kext is loaded but on a different leaf, irrelevant to this code path.

4. **Why Iter 1–4 all "felt the same"**: every iteration was swapping I2C-side kext versions (2.9.1 ↔ 2.8, enabled ↔ disabled). None of them mattered, because the touchpad was on PS/2 and I2C-side changes don't affect PS/2 binding. We were debugging an inert leg of the device tree.

5. **Why fast 2-finger fling was being recognized as 2-finger tap** (the symptom that finally forced reopening the issue): PS/2 InterTouch caps multi-touch sample rate at ~80–100 Hz with serialised per-finger packets. Fast flings emit only contact-down + contact-up samples within the gesture window, with not enough intermediate position frames for `AppleMultitouchTrackpadHIDEventDriver` to detect movement — so it falls back to "tap". I2C HID is GPIO-interrupt-driven and delivers full multi-finger frames per report at hundreds Hz; it has the headroom Linux/Win10 have on this same hardware.

6. **TrackPoint enumeration mapping**: `IOHIDInterface id 0x10000053d` shows `Product = "Mouse"`, `Transport = "PS2"`, served by stock `IOHIDEventDriver` — proving the TrackPoint nub is on its own independent PS/2 mouse channel, not tunneled through Synaptics InterTouch pass-through. Therefore disabling `VoodooPS2Trackpad` is safe for TrackPoint.

**Step 2 — apply T3** (config-only change in `WIP/EFI/OC/config.plist`):
- `VoodooI2CHID.kext`: `Enabled = false → true` (claims `_CID = PNP0C50` SYNA3071 on I2C bus)
- `VoodooPS2Controller.kext/.../VoodooPS2Trackpad.kext`: `Enabled = true → false` (avoid double-binding once I2C side is live)
- `VoodooI2CSynaptics.kext`: `Enabled = true → false` (was never matching; keeping it enabled adds nothing)

User mounted ESP, copied WIP/EFI to /Volumes/EFI/EFI, rebooted.

**Step 3 — verify** (`~/Desktop/trackpad-diagnose-20260425-1631.txt`):
- ✅ kextstat now lists `com.alexandred.VoodooI2CHID (1)` loaded
- ✅ kextstat does NOT list `VoodooI2CSynaptics` or `VoodooPS2Trackpad` (correctly disabled)
- ✅ IOReg: `VoodooI2CControllerDriver → SYNA3071 → VoodooI2CHIDDevice (Transport=I2C) → IOHIDInterface (id 0x1000003be, ProductID=626 'Magic Trackpad 2') → AppleMultitouchTrackpadHIDEventDriver`
- ✅ `ApplePS2SynapticsTouchPad` no longer present in IOReg
- ✅ TrackPoint nub: still enumerated as IOHIDInterface, `Transport=PS2`, `Product="Mouse"`, served by `VoodooPS2Mouse` → working
- ✅ User confirms: 4-finger / 5-finger gestures fire reliably, 2-finger fling produces decaying scroll event stream (no longer recognized as tap), pointer movement smoothness matches Linux/Win10 reference

**Step 4 — cleanup** (alongside Iter 9 EFI delta):
- Removed `VoodooI2CAtmelMXT.kext`, `VoodooI2CELAN.kext`, `VoodooI2CFTE.kext`, `VoodooI2CSynaptics.kext` from both `WIP/EFI/OC/Kexts/` and `11/BCM94352z/EFI/OC/Kexts/`, plus their dict entries from `config.plist Kernel.Add` array. None match this hardware.
- Removed `HP-Elitebook-840-G5/VoodooI2C-2.9.1-RELEASE/` staging directory (Iter 1 leftover, never used).
- Promoted WIP/EFI → `11/BCM94352z/EFI/` baseline (rsync mirror); side-effect picked up the `SSDT-DISABLE-FP.dsl` v2 documentation prose that Iter 7 had landed in WIP but Iter 8 promotion missed.

**Lessons (carry forward)**:
- *Always check kextstat for kext-load confirmation before reasoning about driver chain.* If a kext is "enabled in config" but absent from kextstat, the IOPropertyMatch failed and the kext is inert. Iter 1–8 would have been one iteration if kextstat had been re-read at any point.
- *The DSDT `_HID/_CID` and the macOS-runtime `IOName` are not always the same.* SOURCE-OF-TRUTH SSDTs say one thing (TPD0 / SYNA2393); IOReg says another (SYNA3071 / PNP0C50). Both can be true simultaneously — the SSDT defines the device, the runtime IOReg shows what enumerated. If a kext's IOPropertyMatch is keyed on the wrong field, it never binds.
- *Dual-bus enumeration is real on this hardware.* The PS/2 emulation lane stays active even when I2C path is unclaimed. PS/2 wins by default if no I2C driver matches. Iter 9's fix is "explicitly claim I2C side AND silence PS/2 side", not "swap one I2C kext for another".

### Iteration 1 — ❌ failed both fronts

**Config delta from baseline**:
- Kext bundle bumped to 2.9.1 (VoodooI2C, VoodooI2CSynaptics, VoodooI2CHID, standalone VoodooInput)
- boot-args: `+igfxonln=1 -igfxblr`

**Boot result**: clean boot to GUI, system functional

**Trackpad smoothness**: 1/5 (no change in jitter; same as before)

**Trackpad regression**: 4-finger and 5-finger gestures **completely broken** under 2.9.1 (worked with 2.8 baseline). User checked System Information → USB → trackpad reports as `0x138a:0x00ab` (Synaptics raw HID), **NOT** `0x05ac:0x0265` (Magic Trackpad 2). This means **VoodooInput is NOT presenting the device as Magic Trackpad to macOS** under the 2.9.1 stack — macOS treats it as raw HID, only single/dual-finger gestures route. Hypothesis: VoodooI2CSynaptics 2.9.1 + VoodooInput 1.1.6 integration is broken on Big Sur, OR the stock 2.9.1 build of VoodooI2CSynaptics doesn't enable Magic Trackpad emulation by default and needs additional Info.plist tuning.

**Sleep/wake (lid close)**:
- Test A (30s lid close): screen relit OK, **but power LED never blinked** → system did NOT actually enter S3 sleep. `igfxonln=1` keeps iGPU framebuffer online, effectively preventing sleep entirely.
- Test B (5min lid close): same as A — screen back, no real sleep
- Test C (Apple menu → Sleep): screen blacked for ~1s, then immediately reawoke. Failed: system can't enter sleep at all.
- Test D (30min lid close): skipped — sleep is broken-by-design, no point testing duration

**Net assessment**: `igfxonln=1` is "disable sleep" not "fix sleep". The kext upgrade made trackpad worse. Iter 1 = full negative.

### Iteration 2 — ❌ both still failing

**Trackpad**: same as Iter 1 ("和刚才那一版没啥区别") — 2.8 baseline didn't actually restore working state. Either (a) Iter 1's 2.9.1 swap didn't truly break anything that 2.8 brings back, the trackpad is just consistently bad in this Big Sur boot, OR (b) something in the post-install state of macOS (kext cache, prebuilt link, login session) doesn't pick up the kext rollback as expected. User decision: stop iterating I2C drivers, **try PS/2 path** even though G5 hardware is nominally I2C-only.

**Sleep**: identical to Iter 1 — power LED stays on (no real S3 entry), Apple menu Sleep blacks screen for 0.5s then immediately wakes. Adding `enable-backlight-registers-fix` DeviceProperty + dropping `igfxonln=1` did NOT change the picture. **Diagnosis must shift**: the issue is not iGPU framebuffer recovery, it's that the system **never enters S3 in the first place**. Some component (USB / BT / Wi-Fi / EC) is either vetoing the sleep transition or generating an immediate wake event.

### Iteration 3 — partial diagnosis, both fronts inconclusive

**Trackpad (T-PS2 attempt)**: User reports "和之前没区别" — *zero* perceptible change after disabling all VoodooI2C kexts. Captured `kextstat` shows the actual driver chain in this state:
- VoodooI2C parent kext: not in kextstat (correctly disabled)
- VoodooI2CSynaptics: not loaded (correctly disabled)
- VoodooPS2Trackpad: loaded but does nothing (G5 hardware doesn't expose touchpad surface to PS/2 controller, only TrackPoint nub)
- **`AppleIntelLpssI2C` + `AppleIntelLpssI2CController` (macOS stock): loaded** — this is what's actually driving the trackpad surface
- `AppleTopCaseHIDEventDriver`: stock Apple HID driver atop the I2C HID device

**Conclusion**: macOS's stock I2C HID stack has been driving the touchpad all along. Nothing we change on the third-party kext side meaningfully alters input. The trackpad's actual report descriptor (firmware-baked, can't change) likely doesn't expose Magic Trackpad-style multi-finger reports, so even VoodooInput can't synthesize 4/5-finger gestures from it. **This is the upper limit of this hardware × Big Sur combo.** Recommended action: re-enable VoodooI2C + VoodooI2CSynaptics (at least the SYNA2393 IOPropertyMatch path is preserved) and accept the jitter; long-term solution is external pointing device.

**Side note**: previously suspected USB device `0x138a:0x00ab` on the trackpad track is actually the **Validity / Synaptics fingerprint reader**, NOT the touchpad. (Vendor 0x138a = Validity Sensors, HP G5 standard fingerprint reader.) The actual touchpad is on the I2C bus and doesn't enumerate as USB at all.

**Sleep**: pmset/syslog data revealed the actual chain — sleep IS being entered, but stops at Dark Wake:
- 12:09:25 — first lid close detected, but `clamshell sleep on close: NO` (macOS policy delay)
- 12:09:44 — 19s later policy flips to YES, kernel logs `sleep reason Clamshell Sleep`, `kIOMessageSystemWillSleep` fires, drivers ack
- 12:09:44.565 — `dasd: Entering dark wake` — system enters Dark Wake instead of progressing to S3
- system stays in Dark Wake until `darkwakelinger` 15s timer expires; then a *new* darkwakelinger is created (because background tasks aren't done) → loop. Power LED never breathes because Dark Wake isn't deep sleep.
- 12:10:49 — user opened lid, full wake.

`Total Sleep/Wakes since boot: 0` — system never entered real S3.

This is the **classic Hackintosh "Dark Wake stuck on AC"** pattern. On AC, macOS deliberately stays in Dark Wake for push/AirDrop maintenance and only progresses to S3 after various background completions. On battery, the policy is much more aggressive about progressing to S3.

### Iteration 8 — accidental GOLDEN, SSDT disabled, sleep works cleanly

**Hugely surprising result.** User backed up an EFI variant they called "v6" / GOLDEN. Inspection shows it's **structurally identical to Iter 6-rollback / Iter 5 EFI**: SSDT-DISABLE-FP.aml present on disk but `<false/>` in config.plist (i.e., not loaded by OC). So FP, BT, camera all enumerate normally.

User report: **with this GOLDEN config, lid close AND Apple-menu Sleep both enter S3 cleanly, power LED breathes, all hardware (touchpad, TrackPoint, USB-A both sides, audio in/out, camera, ethernet) functional**.

But Iter 5 had IDENTICAL config and reported the 11-12s periodic XDCI wake. What changed?

**The only persistent state we modified between Iter 5 and now is NVRAM via the `pmset -a` commands the sleep-diagnose.sh script ran each iteration (Iter 4 / 5 / 6 / 7)**:
```
womp 0 / tcpkeepalive 0 / networkoversleep 0 / powernap 0
hibernatemode 0 / standby 0 / autopoweroff 0
proximitywake 0 / sleepservicestimeout 1 / darkwakes 0
```

These PERSIST across reboots (writes to `nvram` / pmset's plist storage). Some combination of these, applied across 4+ test sessions, evidently silences the periodic XDCI wake we previously attributed to FP.

**Revised hypothesis** (replacing the "Validity FP wakes every 11-12s" theory from Iter 6):
- The 11-12s wake periodicity was probably **macOS's own Sleep Services / Power Nap heartbeat**, not the FP USB device firing wake interrupts directly.
- `sleepservicestimeout 1` (Sleep Services window shrunk to 1 second) and/or `proximitywake 0` (Continuity wake disabled, removes a BT-mediated wake event source) cuts off whatever XDCI activity was driving the wake.
- The FP USB device (`0x138a:0x00ab`) was just enumerated like any other USB device; XDCI wake source naming pointed at the controller, not the FP specifically.
- Iter 6's SSDT-DISABLE-FP "fixed" sleep coincidentally (because by hiding HS07 we masked one possible source of XHCI activity), but its real success was **also adding wake-source diagnostic that pmset settings could pick up via separate path**.

**Revised pattern moving forward**:
- WIP/EFI/ now matches GOLDEN: SSDT-DISABLE-FP.aml stays on disk but `Enabled=false` in config — **kept as a spare tire** in case FP misbehavior recurs.
- The pmset NVRAM settings stay applied (no opt-out unless user explicitly resets NVRAM via OC picker → ResetNVRAM entry).
- BT, touchpad, all hardware fully functional; periodicity gone.

**If user ever does NVRAM reset**: pmset settings revert to defaults, periodic wake might return. Recovery: re-run `sleep-diagnose.sh` STEP 2 to re-apply pmset settings. Or persist via boot-args / OpenCore NVRAM > Add (would need to find equivalent OC config keys).

**Promote candidate**: this WIP/EFI is the new baseline candidate for `11/BCM94352z/EFI`. Need to verify across cold boot and multiple sleep cycles before promoting (next iteration's user task).

---

### Iteration 5 — BT off probe, isolated periodicity to non-BT device

User turned off Bluetooth in System Settings (verified: `defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState` = 0), retested lid-close on battery. Result:

```
14:11:06 → 14:11:18  Sleep 12s, Wake "due to XDCI/HID Activity"
14:12:04 → 14:12:15  Sleep 11s, DarkWake "due to XDCI"
```

**Wake source still XDCI, period still 11-12s** — same fingerprint as Iter 4. BT is **not** the periodic wake source. Process of elimination on the XHCI internal devices points to **Validity / Synaptics fingerprint reader** (`0x138a:0x00ab`, location ID `0x14700000` → port 7 → DSDT `\_SB.PCI0.XHC.RHUB.HS07`). Validity sensors have well-documented spurious USB wake behavior on Hackintosh.

User's own observation matches the log: "好像看到 Wi-Fi 和硬盘 LED 熄灭的一瞬间又亮了" — Wi-Fi/HDD LEDs briefly off then on every 11-12 seconds is exactly the S3-then-immediate-wake cycle.

### Iteration 6 — SSDT-DISABLE-FP to mask the fingerprint USB port

Verified DSDT path of fingerprint reader port:
```
\_SB.PCI0.XHC.RHUB.HS07     // _ADR = 0x07, has _UPC + _PLD but no _STA
```

Since DSDT didn't define `_STA` for HS07, we can extend the device cleanly via SSDT and add a `_STA` that returns Zero on macOS, hiding the port entirely. With no driver attaching, no wake events possible.

**Concrete deltas vs Iter 5**:
- New file: `WIP/EFI/OC/ACPI/SSDT-DISABLE-FP.aml` (compiled from `.dsl` source, 116 bytes, 0 errors/warnings via `iasl 20260408`)
- config.plist `ACPI > Add` array gets a new entry for `SSDT-DISABLE-FP.aml` (Enabled=true)
- No boot-arg changes
- No kext changes
- No DeviceProperties changes
- Bluetooth can be turned back ON in System Settings (we ruled it out as wake source)

**Acceptance**:
- pmset log shows wake source no longer "due to XDCI" on lid-close test
- Sleep cycle proceeds beyond 11-12s into stable S3
- Power LED breathes within seconds of lid close

**If Iter 6 fails** (unlikely but possible): camera (HS08) is the only remaining XHCI internal device. Same SSDT pattern would mask HS08. Or escalate to USBPorts.kext rebuild via USBToolBox.

**Tradeoff accepted**: macOS can't use the fingerprint reader. Mainstream macOS Hackintosh kexts don't support Validity fingerprint readers anyway. BIOS toggle (Advanced → Built-in Device Options) achieves the same effect at the hardware layer without any EFI changes — user can prefer that route if BIOS exposes the toggle and dual-boot Linux fingerprint isn't desired.

### Iteration 4 — accept trackpad, retest sleep on battery

**Trackpad**:
- Re-enable `VoodooI2C.kext` + `VoodooI2CSynaptics.kext` (SYNA2393 IOPropertyMatch already in their Info.plist). Doesn't fix the jitter but restores the path that's at least Synaptics-aware. Mark trackpad as **frozen** — no more iteration; jitter is the upper bound on Big Sur for this exact hardware.
- Long-term workaround: external Magic Trackpad / Magic Mouse via BT works perfectly (we verified BT works in Iter 0 — AirDropped bluetooth.txt as proof).

**Sleep — diagnostic-driven Iter 4**:
- Scripted additions: `pmset -a proximitywake 0` (disable Continuity proximity wake via BT), `pmset -a sleepservicestimeout 1` (shrink Sleep Services window).
- **Critical: test on BATTERY (unplug AC)**. macOS Dark Wake policy on battery is much shorter — system should progress to S3 within seconds. If yes → "AC = Dark Wake, Battery = S3" is by design and expected; user accepts AC behavior or applies one of the longer-term workarounds (NVRAM clamshell-sleep override, or live with it).
- If battery sleep STILL fails → deeper ACPI _LID issue or driver wake bug; would write SSDT-LIDFIX or block specific drivers from generating wake events.

**Concrete deltas vs Iter 3**:
- `VoodooI2C.kext` Enabled: false → **true**
- `VoodooI2CSynaptics.kext` Enabled: false → **true**
- `sleep-diagnose.sh` script: add 3 pmset settings + battery instruction in lid-close prompt
- No new boot-args, no DeviceProperties changes, no SSDT additions.


## Hardware-side things to also check post-Big-Sur

(unrelated to trackpad/sleep but worth noting once they're fixed)

- [ ] HP Fn key remapping (port `SSDT-INPUT.aml` from reference repo, adapt to PS2K path)
- [ ] USBPorts.kext audit — current one is inherited from reference; build a real one with USBToolBox after sleep is fixed
- [ ] CPU power management: verify `pmset -g log` shows clean P-state transitions
- [ ] Battery reporting: verify `% remaining` updates correctly under load

## Future macOS upgrade decision (post Big Sur stabilization)

See README.md "BT card decision matrix". Current strategic answer: stay on Big Sur for daily, when wanting newer macOS swap card to Fenvi BCM94360NG (path D), don't fight BCM94352Z on Monterey+.
