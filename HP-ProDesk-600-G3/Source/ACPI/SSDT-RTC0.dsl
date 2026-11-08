/*
 * HP ProDesk 600 G3 DM: DSDT RTC (PNP0B00) _STA is gated on STAS==1 and BIOS leaves it off
 * (Linux dump: "rtc_cmos: registered fallback platform RTC device"). No AWAC device exists.
 * SSDT-AWAC style "STAS = One" is module-level Store, which Mojave ACPICA 20160930 ignores
 * ("Unsupported module-level executable opcode 0x70"), so use a fake RTC0 instead.
 * Source: OpenCorePkg 1.0.8 Docs/AcpiSamples/Source/SSDT-RTC0.dsl (path LPCB matches).
 */

DefinitionBlock ("", "SSDT", 2, "ACDT", "RTC0", 0x00000000)
{
    External (_SB_.PCI0.LPCB, DeviceObj)    // (from opcode)

    Scope (_SB.PCI0.LPCB)
    {
        Device (RTC0)
        {
            Name (_HID, EisaId ("PNP0B00"))  // _HID: Hardware ID
            Name (_CRS, ResourceTemplate ()  // _CRS: Current Resource Settings
            {
                IO (Decode16,
                    0x0070,             // Range Minimum
                    0x0070,             // Range Maximum
                    0x01,               // Alignment
                    0x08,               // Length
                    )
                IRQNoFlags ()
                    {8}
            })
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (_OSI ("Darwin")) {
                    Return (0x0F)
                } Else {
                    Return (0);
                }
            }
        }
    }
}
