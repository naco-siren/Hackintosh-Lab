#!/usr/bin/env python3
"""Build config.plist for HP ProDesk 600 G3 DM (i5-7500T / HD630 / Q270) -> macOS Catalina + Ventura
(one EFI; Ventura-only kexts gated by MinKernel. Mojave attempted in Iter 1-4, its bits removed in Iter 5).

Base: OpenCore 1.0.8 Docs/Sample.plist, then overridden per Dortania Kaby Lake desktop
guide + Configuration.pdf. Every non-default choice carries its reason inline.

usage: make_config.py <Sample.plist> <out config.plist> <release|debug> [smbios.local.plist]
       make_config.py --layout      -> prints "<macOS>/<WLAN>" (the EFIs/ sub-path build.sh uses)
"""
import os
import plistlib
import sys

# What this EFI is for. One place: build.sh derives the EFIs/<macOS>/<WLAN>/ path from LAYOUT, and the same
# values land in config.plist "#Hardware" (keys starting with '#' are comments to OpenCore, Configuration.pdf
# "Configuration Terms"), so a copied-out EFI still says which machine/card it needs.
MACHINE = "HP ProDesk 600 G3 DM (i5-7500T / HD 630 / Q270)"
MACOS = "13"            # Ventura validated; the same EFI is also built for Catalina 10.15 (MinKernel gating)
WLAN = "BCM943224PCIEBT2"
WLAN_DESC = "Apple BCM943224PCIEBT2: Wi-Fi BCM43224 (PCIe 14e4:4353) + USB Bluetooth (Apple VID 05ac)"
WLAN_BOOT_ARGS = ["-btlfxallowanyaddr"]
LAYOUT = f"{MACOS}/{WLAN}"
KNOWN_ISSUES = [
    "SLEEP IS BROKEN: waking from sleep with a DisplayPort monitor attached freezes the machine (black "
    "screen, needs a hard reset). Disable sleep: `sudo pmset -a sleep 0` (display sleep still works), "
    "or unplug DP before sleeping and re-plug after wake.",
]


def drv(path, comment, load_early=False):
    return {"Arguments": "", "Comment": comment, "Enabled": True, "HideVerbose": False,
            "LoadEarly": load_early, "Path": path}


def kext(bundle, comment, exe=True, min_kernel="", wlan=False):
    # wlan=True: only needed for the WLAN card above -> "[WLAN]" tag + listed in "#Hardware"
    name = bundle.split("/")[-1].removesuffix(".kext")
    return {"Arch": "Any", "BundlePath": bundle, "Comment": ("[WLAN] " if wlan else "") + comment, "Enabled": True,
            "ExecutablePath": f"Contents/MacOS/{name}" if exe else "",
            "MaxKernel": "", "MinKernel": min_kernel, "PlistPath": "Contents/Info.plist"}


def ssdt(path, comment):
    return {"Comment": comment, "Enabled": True, "Path": path}


def main(sample, out, flavour, smbios_path=None):
    p = plistlib.load(open(sample, "rb"))

    # ---------------- ACPI ----------------
    p["ACPI"]["Add"] = [
        ssdt("SSDT-PLUG.aml", "plugin-type=1 on \\_PR.PR00 (XCPM; needed < Monterey)"),
        ssdt("SSDT-EC.aml", "Fake EC 'EC' + disable real EC0 under Darwin (desktop: Dortania recommends disabling PNP0C09)"),
        ssdt("SSDT-USBX.aml", "USBX power properties"),
        ssdt("SSDT-RTC0.aml", "Fake RTC0: DSDT RTC disabled via STAS (Linux fell back to platform RTC). Iter 3"),
        ssdt("SSDT-GPRW.aml", "GPRW 0x6D -> sleep state 0 under Darwin (GLAN/XDCI/HDAS); instant wake 'due to XDCI'. Iter 13"),
    ]
    p["ACPI"]["Delete"] = []
    p["ACPI"]["Patch"] = [{
        "Base": "", "BaseSkip": 0, "Comment": "EC0._STA -> XSTA (pairs with SSDT-EC; pattern unique in DSDT @0x9f6f)",
        "Count": 1, "Enabled": True,
        "Find": bytes.fromhex("6e14095f535441"), "Replace": bytes.fromhex("6e140958535441"),
        "Limit": 0, "Mask": b"", "OemTableId": b"", "ReplaceMask": b"", "Skip": 0,
        "TableLength": 0, "TableSignature": b"DSDT",
    }, {
        # Dortania usb/misc/instant-wake.md GPRW-Patch.plist (Count 0 there); pinned to the single
        # Method (GPRW, 2) definition in this DSDT (0 matches in the SSDTs). Pairs with SSDT-GPRW.
        "Base": "", "BaseSkip": 0, "Comment": "GPRW -> XPRW (pairs with SSDT-GPRW)",
        "Count": 1, "Enabled": True,
        "Find": bytes.fromhex("4750525702"), "Replace": bytes.fromhex("5850525702"),
        "Limit": 0, "Mask": b"", "OemTableId": b"", "ReplaceMask": b"", "Skip": 0,
        "TableLength": 0, "TableSignature": b"DSDT",
    }]

    # ---------------- Booter ----------------
    b = p["Booter"]
    b["MmioWhitelist"] = []
    b["Patch"] = []
    # Sample defaults already match Dortania KBL desktop (AvoidRuntimeDefrag, EnableSafeModeSlide,
    # EnableWriteUnprotector, ProvideCustomSlide, SetupVirtualMap = YES; DevirtualiseMmio,
    # RebuildAppleMemoryMap, SyncRuntimePermissions = NO). Keep explicit for review:
    b["Quirks"].update({
        "AvoidRuntimeDefrag": True, "DevirtualiseMmio": False, "EnableSafeModeSlide": True,
        "EnableWriteUnprotector": True, "ProvideCustomSlide": True, "RebuildAppleMemoryMap": False,
        "SetupVirtualMap": True, "SyncRuntimePermissions": False,
    })

    # ---------------- DeviceProperties ----------------
    p["DeviceProperties"] = {"Add": {
        "PciRoot(0x0)/Pci(0x2,0x0)": {
            # HD630 desktop, display-out iGPU. 0x59120000 (Dortania Install Guide kaby-lake.md,
            # "Used when the Desktop iGPU is used to drive a display").
            # Iter 14d tried 0x59160000 (GPU-Buyers-Guide intel-gpu.md desktop "(default)") after Linux S3 with
            # DP attached resumed fine here: FB0 became eDP port 0 (absent on this box), DP on FB1 port 5;
            # attached-at-sleep+wake still hung, then rebooted ~30 s later. Reverted.
            "AAPL,ig-platform-id": bytes.fromhex("00001259"),
            # HP business BIOS usually offers no DVMT pre-alloc knob: min stolen mem 19MB.
            # Exactly the Dortania kaby-lake.md DeviceProperties example (fbmem dropped in Iter 3).
            "framebuffer-patch-enable": bytes.fromhex("01000000"),
            "framebuffer-stolenmem": bytes.fromhex("00003001"),
            # No `force-online` (Iter 8 added it per Dortania sleep.md "igfxonln=1 ... test first"; the wake
            # failure it targeted never went away). Iter 14: full wake hangs the box only with a DP display
            # attached (headless full wake OK, ping/ssh alive). Post-wake headless log on FB0:
            # "Display status is = 0" (HPD low) yet AGDC "Port status = 1" -> "Port enable" -> 110x
            # "[AGDC] Failed ... stream access aux" in 6 s; a later DP replug: HPD high -> "Event remove",
            # never lights. The forced-online status is what turns an empty port into a connected one.
            # (Iter 14a `disable-agdc`: no change, removed.)
            # Iter 14b result (force-online gone): headless wake -> DP replug now goes "Event insert" ->
            # link training OK -> FB0 modeset 2560x1080 -> screen lights, no hang. So force-online was
            # what broke post-wake hot-plug. A wake with DP already attached still hard-hangs (open).
            # Iter 14 rule (clean-boot confirmed): hang iff DP attached at sleep entry AND at wake; DP
            # pulled during sleep, or plugged during sleep, both wake fine. I.e. resuming an FB that was
            # online at sleep hangs; lighting a fresh hot-plug after wake works. That restore runs on a
            # port the log marks "Port Managed by AGDC".
            # Iter 14c: retried WEG README `disable-agdc` (= igfxagdc=0) alone, force-online gone
            # (14a had both). Attached-at-sleep+wake still hard-hangs -> AGDC is not it; removed.
        },
        "PciRoot(0x0)/Pci(0x1F,0x3)": {
            # Conexant CX20632. AppleALC layouts for this codec: 20 (EliteDesk 800 G5 mini),
            # 23 (ProDesk 480 G4), 28. Start with 20 (same DM chassis family); test others via alcid=.
            "layout-id": (20).to_bytes(4, "little"),
        },
        # Optane M10 (RP09, 8086:2522): no property. Catalina drives it natively (Fusion with HDD).
    }, "Delete": {}}

    # ---------------- Kernel ----------------
    k = p["Kernel"]
    k["Add"] = [
        kext("Lilu.kext", "Patch engine (must be first)"),
        kext("VirtualSMC.kext", "SMC emulator"),
        kext("SMCProcessor.kext", "CPU temperature"),
        kext("WhateverGreen.kext", "iGPU HD630"),
        kext("AppleALC.kext", "Audio CX20632"),
        kext("IntelMausi.kext", "Ethernet I219-LM 8086:15e3"),
        kext("NVMeFix.kext", "APST/quirks for non-Apple NVMe (Optane M10)"),
        kext("USBMap.kext", "Custom 15-port map for XHC a2af (make_usbmap.py; physically verified Iter 7, budget Iter 7c)", exe=False),
        # ---- Apple BCM943224PCIEBT2 Wi-Fi (BCM43224, 14e4:4353), all macOS versions (Iter 6).
        # Mojave: AirPort_Brcm4360 probes 4353 (score 1400) but fails; AirPort_Brcm4331 took it.
        # Catalina removed AirPortBrcm4331 -> same 4360 probe, nothing attaches (diag 2026-11-06).
        # Big Sur+ removed AirPortBrcm4360 too. OCLP's _wifi_fake_id() for BCM943224/BCM94331:
        # AirportBrcmFixup + AirPortBrcmNIC_Injector (IONameMatch pci14e4,4353 -> AirPort_BrcmNIC,
        # score 2048) -> stock AirPortBrcmNIC drives it. Kext-only, no root patch. Not gated: Catalina
        # needs it as well. (AirPortBrcm4360_Injector is stripped in build.sh, per Fixup README.)
        kext("AirportBrcmFixup.kext", "Broadcom Wi-Fi fixups (Lilu plugin)", wlan=True),
        kext("AirportBrcmFixup.kext/Contents/PlugIns/AirPortBrcmNIC_Injector.kext",
             "bind 14e4:4353 to AirPort_BrcmNIC", exe=False, wlan=True),
        # Monterey+ moved BT host logic into bluetoothd/BlueTool and dropped 20702_821F firmware:
        # official acidanthera BlueToolFixup (OCLP: BRCM20702 Hub + 4360-class Wi-Fi -> BlueToolFixup only).
        # Card already reports Apple VID 05ac, so no chipset-detection patch is needed (verified on Ventura).
        kext("BlueToolFixup.kext", "Monterey+: Bluetooth host fixup", min_kernel="21.0.0", wlan=True),
    ]
    k["Block"] = []
    k["Force"] = []
    k["Patch"] = []
    k["Quirks"].update({
        "AppleXcpmCfgLock": True,        # HP BIOS: CFG Lock not unlockable
        "DisableIoMapper": True,         # VT-d on in BIOS is fine with this
        "DisableLinkeditJettison": True,
        "LapicKernelPanic": True,        # HP-specific LAPIC panic (Dortania: HP systems)
        "PanicNoKextDump": True,
        "PowerTimeoutKernelPanic": True,
        "XhciPortLimit": False,          # replaced by USBMap.kext (13 <= 15 ports)
    })

    # ---------------- Misc ----------------
    m = p["Misc"]
    m["Boot"].update({
        "HideAuxiliary": True, "PickerMode": "External", "PickerVariant": "Acidanthera\\GoldenGate",
        "PickerAttributes": 17, "ShowPicker": True, "Timeout": 5, "PollAppleHotKeys": True,
        "HibernateMode": "None",
    })
    # release = Dortania Post-Install "Fixing Resolution and Verbose": AppleDebug off, Target 3
    m["Debug"].update({"AppleDebug": flavour == "debug", "ApplePanic": True, "DisableWatchDog": True,
                       "Target": 67 if flavour == "debug" else 3,
                       # debug: + DEBUG_INFO so the on-ESP opencore-*.txt log is useful
                       "DisplayLevel": 2147483714 if flavour == "debug" else 2147483650})
    m["Security"].update({
        "AllowSetDefault": True,
        "ScanPolicy": 0,   # show everything (Iter 3b's ESP-hiding 0x00290303 reverted in Iter 4)
        "Vault": "Optional",
        "DmgLoading": "Signed",
        # 'Default' on a non-T2 SMBIOS resolves to x86legacy = minimum macOS 11.0.1
        # (Configuration.pdf SecureBootModel). Dortania security.md, 10.13-10.15: SMBIOS not in
        # the T2 list (iMac18,1 isn't) -> Disabled. Kept Disabled on Ventura too so the same EFI still boots
        # Catalina (Default/x86legacy needs 11.0.1+). Switch to Default once Catalina is gone.
        "SecureBootModel": "Disabled",
    })
    m["Entries"] = []
    m["Tools"] = [{
        "Arguments": "", "Auxiliary": True, "Comment": "OpenShell", "Enabled": True,
        "Flavour": "OpenShell:UEFIShell:Shell", "FullNvramAccess": False, "Name": "UEFI Shell",
        "Path": "OpenShell.efi", "RealPath": False, "TextMode": False,
    }]

    # ---------------- NVRAM ----------------
    nv = p["NVRAM"]["Add"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"]
    nv.pop("#INFO (prev-lang:kbd)", None)
    # debug=0x100 (stay on the panic screen instead of auto-reboot) is a bring-up aid -> DEBUG only.
    # -btlfxallowanyaddr: BlueToolFixup, macOS 12.4+ bluetoothd address check (no-op on Catalina).
    # swd_panic=1 (DEBUG only): Dortania sleep.md, turns a sleep/wake failure into a panic log.
    # (Iter 9 tried forceRenderStandby=0 for the S3-resume hang: no effect -> removed in Iter 10.)
    # (Iter 14e tried panic_on_display_hang=1 panic_on_gpu_hang=1 from the Configuration.pdf boot-arg list:
    # the DP-attached S3-resume hang produced no panic report -> below what the driver detects; removed.)
    nv["boot-args"] = ("-v keepsyms=1 debug=0x100 -liludbgall msgbuf=1048576 swd_panic=1" if flavour == "debug"
                       else "keepsyms=1") + " " + " ".join(WLAN_BOOT_ARGS)
    nv["prev-lang:kbd"] = "en-US:0"
    nv["csr-active-config"] = bytes.fromhex("00000000")
    p["NVRAM"]["Delete"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"] = [
        "boot-args", "ForceDisplayRotationInEFI", "csr-active-config", "prev-lang:kbd"]

    # ---------------- PlatformInfo ----------------
    g = p["PlatformInfo"]["Generic"]
    g.update({"SystemProductName": "iMac18,1",  # KBL desktop, iGPU drives display
              "SystemSerialNumber": "", "MLB": "", "SystemUUID": "", "ROM": b"",
              "ProcessorType": 0, "SpoofVendor": True})
    if smbios_path:
        s = plistlib.load(open(smbios_path, "rb"))
        assert s["SystemProductName"] == "iMac18,1", "SMBIOS model mismatch"
        for key in ("SystemSerialNumber", "MLB", "SystemUUID", "ROM"):
            g[key] = s[key]
    p["PlatformInfo"]["UpdateSMBIOSMode"] = "Create"

    # ---------------- UEFI ----------------
    u = p["UEFI"]
    u["Drivers"] = [
        drv("OpenHfsPlus.efi", "HFS+ (installer USB + Recovery are HFS+)"),
        drv("OpenRuntime.efi", "Required"),
        drv("OpenCanopy.efi", "GUI picker"),
        drv("ResetNvramEntry.efi", "Reset NVRAM picker entry"),
        drv("AudioDxe.efi", "Boot chime via HDA (CX20632)"),
    ]
    # Boot chime. Resources/Audio/OCEFIAudio_VoiceOver_Boot.wav is pre-decoded 16-bit PCM
    # (Conexant codecs reject the 32-bit float PCM produced by OC's mp3 decoder).
    u["Audio"].update({
        "AudioSupport": True, "AudioDevice": "PciRoot(0x0)/Pci(0x1F,0x3)", "AudioCodec": 0,
        "AudioOutMask": -1,          # all outputs: internal speaker + rear line-out
        "PlayChime": "Enabled", "SetupDelay": 0,
    })
    # Catalina's APFS driver predates OC's default floor (Big Sur 1600000000000000 / 2021-01-01).
    # Iter 5: Mojave's "-1 / no restriction" replaced by Dortania kaby-lake.md table row
    # "Catalina (10.15.4)" -> requires a >= 10.15.4 install. Set both back to -1 for older.
    u["APFS"].update({"MinDate": 20200306, "MinVersion": 1412101001000000})
    u["Quirks"].update({
        "UnblockFsConnect": True,   # HP firmware: drives not connected by default (Dortania HP note)
        "RequestBootVarRouting": True,
        "IgnoreInvalidFlexRatio": False,
        "ReleaseUsbOwnership": False,
    })
    u["ReservedMemory"] = []

    # Sleep history: Iter 11 kext bisect (nonvmefix/nomausi/noalc) and Iter 12 noaspm (pci-aspm-default=0 on
    # the Optane link, confirmed applied in ioreg) changed nothing on wake; variants removed in Iter 13.
    # Iter 13 evidence: every S3 sleep was followed ~3 s later by "DarkWake ... due to XDCI" (GPE 0x6D) ->
    # SSDT-GPRW above. Open, separate issue: intermittent IONVMe "Command timeout. Delete IO submission
    # queue" panic on the Optane M10 at sleep entry (2 of ~8 attempts).

    p["#Hardware"] = {
        "Machine": MACHINE,
        "macOS": f"{MACOS} (Ventura); also builds for 10.15 Catalina",
        "WLAN": WLAN_DESC,
        "WLAN-coupled": [f"Kernel/Add: {e['BundlePath']}" for e in k["Add"] if e["Comment"].startswith("[WLAN]")]
                        + [f"boot-args: {a}" for a in WLAN_BOOT_ARGS],
        "KnownIssues": KNOWN_ISSUES,
        "Readme": "HP-ProDesk-600-G3/README.md",
    }

    with open(out, "wb") as f:
        plistlib.dump(p, f)
    print(f"config.plist ({flavour}{', +SMBIOS' if smbios_path else ', blank SMBIOS'}) -> {out}")


if __name__ == "__main__":
    if sys.argv[1:] == ["--layout"]:
        print(LAYOUT)
    else:
        main(*sys.argv[1:])
