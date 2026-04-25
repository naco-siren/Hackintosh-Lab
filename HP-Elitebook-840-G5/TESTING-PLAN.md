# Testing Plan — Trackpad smoothness & Sleep/Wake (Big Sur)

> **Workflow per iteration:** sync `WIP/EFI/` from `11/BCM94352z/EFI/` → apply iteration changes → mount internal SSD ESP from running Big Sur → `cp -R WIP/EFI/* /Volumes/EFI/EFI/` → reboot → test both trackpad and sleep simultaneously → record results in **Iteration log** below → I update the next iteration based on outcomes.

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
