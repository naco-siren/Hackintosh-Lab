/*
 * SSDT-DISABLE-FP.aml — disable the Validity / Synaptics fingerprint reader
 *                        USB port (XHC.RHUB.HS07) unconditionally.
 *
 * v2 (Iter 7): dropped the `If (_OSI ("Darwin"))` gating from v1.
 *
 * Why: OpenCore's existing ACPI > Patch rewrites every `_OSI` bytecode
 * occurrence to `XOSI` across all loaded ACPI tables (DSDT + injected
 * SSDTs). Our injected SSDT-XOSI itself calls `_OSI ("Darwin")` to
 * decide its branch; that call also gets rewritten to `XOSI("Darwin")`,
 * which then recursively calls `XOSI("Darwin")` again at runtime. The
 * recursion either errors out or returns indeterminate, which in v1
 * showed up as the BCM BT (HS06, sibling device) failing to enumerate
 * — likely because BrcmPatchRAM3's firmware injection timing window
 * got disrupted by the malformed ACPI evaluation cascade across the
 * whole XHCI namespace at boot.
 *
 * v2 fixes this by NOT calling _OSI at all. We just unconditionally
 * return Zero, which hides HS07 from every OS that reads the namespace
 * — Linux included. The user's target is macOS-only on this drive, so
 * losing the port on (potential future) Linux boots is acceptable.
 *
 * Iter 5 confirmed FP is the periodic XDCI wake source; Iter 6 with
 * the v1 SSDT delivered "perfect sleep" (LED breathed) but cost BT.
 * v2 keeps the sleep win without the BT loss.
 *
 * Tradeoff still: macOS can't use the fingerprint reader. Mainstream
 * macOS Hackintosh kexts don't support Validity readers anyway.
 *
 * BIOS toggle remains an alternative IF the user can recover the
 * BIOS admin password (currently locked out per Iter 6 message).
 */

DefinitionBlock ("", "SSDT", 2, "OCEFI ", "DISFP", 0x00001001)
{
    External (_SB_.PCI0.XHC_.RHUB.HS07, DeviceObj)

    Scope (\_SB.PCI0.XHC.RHUB.HS07)
    {
        Method (_STA, 0, NotSerialized)
        {
            Return (Zero)
        }
    }
}
