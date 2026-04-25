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

### Iteration 1 — [PENDING]

**Config delta from baseline**:
- Kext: VoodooI2CSynaptics 2.8 → 2.9.1
- boot-args: `+igfxonln=1 -igfxblr`

**Boot result**: TBD
**Trackpad smoothness**: TBD (1=worse, 5=as smooth as Linux/G3 PS/2)
**Sleep/wake**: TBD (works clean / works with delay / black screen / panic)
**Side effects**: TBD

---

## Hardware-side things to also check post-Big-Sur

(unrelated to trackpad/sleep but worth noting once they're fixed)

- [ ] HP Fn key remapping (port `SSDT-INPUT.aml` from reference repo, adapt to PS2K path)
- [ ] USBPorts.kext audit — current one is inherited from reference; build a real one with USBToolBox after sleep is fixed
- [ ] CPU power management: verify `pmset -g log` shows clean P-state transitions
- [ ] Battery reporting: verify `% remaining` updates correctly under load

## Future macOS upgrade decision (post Big Sur stabilization)

See README.md "BT card decision matrix". Current strategic answer: stay on Big Sur for daily, when wanting newer macOS swap card to Fenvi BCM94360NG (path D), don't fight BCM94352Z on Monterey+.
