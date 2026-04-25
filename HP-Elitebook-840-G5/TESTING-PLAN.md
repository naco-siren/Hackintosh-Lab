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

### Iteration 3 — [PENDING]

**Strategy**: pivot both fronts.

**Trackpad — T-PS2 (full PS/2 path)**:
- Config-disable `VoodooI2C.kext` + `VoodooI2CSynaptics.kext` (kept on disk, just `Enabled=false` for easy rollback)
- VoodooI2CHID was already disabled
- `VoodooPS2Controller` + `VoodooPS2Trackpad` + `VoodooPS2Mouse` + `VoodooPS2Keyboard` already enabled
- Standalone `VoodooInput.kext` stays enabled (PS/2 trackpad uses it for Magic Trackpad emulation)
- **PHYSICAL CAVEAT**: G5's touchpad is wired as I2C-HID at the chipset level. PS/2 path can only see it if BIOS exposes a "legacy PS/2" mode. User to check **BIOS → Advanced → look for "Touchpad: Native / Legacy" or "Legacy support"** before booting Iter 3.
- Worst case: trackpad surface dead, but TrackPoint nub (PS/2 native) still works, and Iter 4 swings back to T2 (VoodooRMI) or T3 (VoodooI2CHID).

**Sleep — diagnostic-first + S5**:
- Add `hbfx-ahbm=1` boot-arg (HibernationFixup forces pure S3, disables hibernate which can mask wake-veto issues)
- **Run pmset diagnostic before next test** to identify what's preventing sleep:
  ```
  sudo pmset -g log | grep -iE "sleep|wake|powerd|denied" | tail -100
  pmset -g assertions
  log show --last 5m --predicate 'eventMessage CONTAINS "sleep" OR eventMessage CONTAINS "wake"' | tail -50
  ```
- Common Hackintosh wake-immediate culprits to look for in output:
  - `kernel: AppleACPIPlatform` mentions wake source = `EC` / `XHC` / `RP*` / `GLAN`
  - `IOPMrootDomain: assertion` from BCM Wi-Fi or BT
  - `kernel: USBF` resume events from a peripheral
- Next iteration's sleep moves depend on what the log says.

**Concrete config.plist deltas vs Iter 2**:
- VoodooI2C.kext Enabled: true → false
- VoodooI2CSynaptics.kext Enabled: true → false
- boot-args: append ` hbfx-ahbm=1`

**Config delta from baseline**:
- Kext: revert VoodooI2C / VoodooI2CSynaptics / VoodooI2CHID / VoodooInput to baseline 2.8 / 1.1.3 (preserve baseline behavior on trackpad)
- boot-args: drop `igfxonln=1`, **keep** `-igfxblr` only
- DeviceProperties `PciRoot(0x0)/Pci(0x2,0x0)`: add `enable-backlight-registers-fix = <01000000>` (the actual companion to `-igfxblr` — without this, `-igfxblr` alone is partially active)

**What this isolates**:
- Trackpad: should return to baseline state (1/5 jitter but 4/5-finger works) — confirms 2.9.1 was the regression
- Sleep: should now ACTUALLY enter S3 (power LED blinks) AND wake cleanly (screen relit by registers-fix)

**Acceptance criteria**:
- Power LED **blinks** (or breathes) on lid close → confirms real sleep entered
- Lid open → screen relights within 1-2s → confirms registers-fix works
- Apple menu → Sleep → black screen → press key → screen back

**If sleep works in Iter 2**: trackpad becomes Iter 3's exclusive focus. Likely path: T3 (disable VoodooI2CSynaptics, enable VoodooI2CHID — different driver, different VoodooInput integration).

**If sleep still broken in Iter 2**: add S4 (`enable-backlight-smoother`) + S5 (`hbfx-ahbm=1`) in Iter 3. Last resort = SSDT-LIDFIX (S6).

---

## Hardware-side things to also check post-Big-Sur

(unrelated to trackpad/sleep but worth noting once they're fixed)

- [ ] HP Fn key remapping (port `SSDT-INPUT.aml` from reference repo, adapt to PS2K path)
- [ ] USBPorts.kext audit — current one is inherited from reference; build a real one with USBToolBox after sleep is fixed
- [ ] CPU power management: verify `pmset -g log` shows clean P-state transitions
- [ ] Battery reporting: verify `% remaining` updates correctly under load

## Future macOS upgrade decision (post Big Sur stabilization)

See README.md "BT card decision matrix". Current strategic answer: stay on Big Sur for daily, when wanting newer macOS swap card to Fenvi BCM94360NG (path D), don't fight BCM94352Z on Monterey+.
