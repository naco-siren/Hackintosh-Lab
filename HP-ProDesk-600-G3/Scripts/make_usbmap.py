#!/usr/bin/env python3
"""Generate USBMap.kext for HP ProDesk 600 G3 DM (Q270, XHC 8086:a2af), macOS 10.15+.

Port list derived from DSDT \\_SB.PCI0.XHC.RHUB: _UPC (connectable/type) + _PLD (group position,
panel bits 67-69: 4=front 5=back). Physically verified on Ventura 2026-11-06 with corpnewt USBMap:
its kext had exactly the 13 addresses below (renamed HS06=0x0d, HS07=0x0e, SS06=0x17).

  back  (Data)     HS01/SS01 lower, HS02/SS02 upper      all four rear A ports are USB3 (HS+SS)
  back  (KB/Mouse) HS04/SS04 lower, HS05/SS05 upper
  front A          HS03/SS03 right, HS13/SS07 middle
  front C (left)   HS09 + SS08 + SS09   _UPC 0x0A = Type-C *without* switch: one SS port per
                   plug orientation -> needs all three for USB3 in both orientations.
  internal         HS14 = BCM943224PCIEBT2 Bluetooth

Port budget (user's choice): front C gets full HS09+SS08+SS09 (16 needed, 15 allowed), paid for by
  SS04            rear KB/Mouse lower -> USB2 only (HP intends that pair for keyboard/mouse)
  (Iter 7b dropped HS01+SS04+SS05 = 13 ports; Iter 7c restored HS01 and SS05 -> 15 ports, at the limit)

Not mapped:
  SS04            dropped on purpose (port budget, above)
  HS07/SS06       _UPC 0x09 rear Type-C, connectable only if GG18==0 = optional Flex IO module
                  (not fitted on this unit)
  HS06 HS08 HS10 HS11 HS12 USR1 USR2 SS10: _UPC not connectable
"""
import plistlib
import sys
from pathlib import Path

USB3_A = 3
TYPE_C_NOSWITCH = 0x0A   # ACPI _UPC / UsbConnector: Type-C USB2+SS without switch
INTERNAL = 255

# name: (port address, UsbConnector, comment)
PORTS = {
    "HS01": (0x01, USB3_A, "back Data lower (USB2 half)"),
    "HS02": (0x02, USB3_A, "back Data upper (USB2 half)"),
    "HS03": (0x03, USB3_A, "front A right (USB2 half)"),
    "HS04": (0x04, USB3_A, "back KB/Mouse lower (USB2 half)"),
    "HS05": (0x05, USB3_A, "back KB/Mouse upper (USB2 half)"),
    "HS09": (0x09, TYPE_C_NOSWITCH, "front C left (USB2, both orientations)"),
    "HS13": (0x0D, USB3_A, "front A middle (USB2 half)"),
    "HS14": (0x0E, INTERNAL, "Internal: BCM943224PCIEBT2 Bluetooth (BRCM20702 Hub 0a5c:4500 -> HCI 05ac:821f)"),
    "SS01": (0x11, USB3_A, "back Data lower (SS half)"),
    "SS02": (0x12, USB3_A, "back Data upper (SS half)"),
    "SS03": (0x13, USB3_A, "front A right (SS half)"),
    # SS04 (back KB/Mouse lower, SS half) dropped for the port budget -> that port is USB2-only
    "SS05": (0x15, USB3_A, "back KB/Mouse upper (SS half)"),
    "SS07": (0x17, USB3_A, "front A middle (SS half)"),
    "SS08": (0x18, TYPE_C_NOSWITCH, "front C left (SS, plug orientation A)"),
    "SS09": (0x19, TYPE_C_NOSWITCH, "front C left (SS, plug orientation B)"),
}


def le32(n: int) -> bytes:
    return n.to_bytes(4, "little")


def main(out_dir: str) -> None:
    assert len(PORTS) <= 15, "15-port limit exceeded"
    kext = Path(out_dir) / "USBMap.kext" / "Contents"
    kext.mkdir(parents=True, exist_ok=True)
    # Port entry layout = corpnewt USBMap.py output (port + usb-port-number, UsbConnector + usb-port-type)
    ports = {
        name: {"name": name, "port": le32(addr), "usb-port-number": le32(addr),
               "UsbConnector": conn, "usb-port-type": conn, "Comment": cmt}
        for name, (addr, conn, cmt) in PORTS.items()
    }
    info = {
        "CFBundleDevelopmentRegion": "English",
        "CFBundleIdentifier": "com.hackintosh-lab.USBMap.ProDesk600G3",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "USBMap",
        "CFBundlePackageType": "KEXT",
        "CFBundleShortVersionString": "1.0",
        "CFBundleSignature": "????",
        "CFBundleVersion": "1.0",
        "OSBundleRequired": "Root",
        "IOKitPersonalities": {
            "XHC-a2af": {
                # 10.15+ merge class (corpnewt USBMap: AppleUSBHostMergeProperties MinKernel 19.0.0;
                # AppleUSBMergeNub only up to 18.9.9 = Mojave, used in Iter 1-4)
                "CFBundleIdentifier": "com.apple.driver.AppleUSBHostMergeProperties",
                "IOClass": "AppleUSBHostMergeProperties",
                # Iter 6: matching rewritten to corpnewt USBMap.py's form. Iter 1-5 used
                # IOProviderClass AppleUSBXHCIPCI + IOPCIPrimaryMatch, which never matched on
                # Catalina: ioreg showed ports HS07/HS09 (not in this map) and no HS14, i.e. the
                # iMac18,1 ACPI _UPC-based layout, where HS14 (BT) is "not connectable".
                "IOProviderClass": "AppleUSBXHCISPT",              # actual class from Catalina ioreg
                "IOParentMatch": {"IOPropertyMatch": {"pcidebug": "0:20:0"}},  # XHC@14 PCI device
                "model": "iMac18,1",
                "IOProviderMergeProperties": {
                    "kUSBMuxEnabled": True,
                    "port-count": le32(max(a for a, _, _ in PORTS.values())),
                    "ports": ports,
                },
            }
        },
    }
    with open(kext / "Info.plist", "wb") as f:
        plistlib.dump(info, f)
    print(f"USBMap.kext: {len(PORTS)} ports -> {kext.parent}")


if __name__ == "__main__":
    main(sys.argv[1])
