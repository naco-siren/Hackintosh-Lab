/*
 * HP ProDesk 600 G3 DM: S3 instant wake via GPE 0x6D.
 * pmset log (Iter 13): "DarkWake from Normal Sleep [CDN] : due to XDCI/" ~3 s after every sleep,
 * kernel: "Wake reason: XDCI", "system wake events: XDCI XHC".
 * DSDT: \GPRW (Method (GPRW, 2), root scope) is called as GPRW (0x6D, 0x04) by GLAN, XDCI and HDAS.
 * XHC has its own _PRW {0x6D, 0x03} and is untouched, so USB keyboard/mouse wake keeps working.
 * Pairs with the ACPI patch GPRW -> XPRW ("4750525702" -> "5850525702", 1 match in DSDT, 0 in SSDTs).
 * Source: dortania/OpenCore-Post-Install extra-files/SSDT-GPRW.aml (usb/misc/instant-wake.md), verbatim.
 */

DefinitionBlock ("", "SSDT", 2, "DRTNIA", "GPRW", 0x00000000)
{
    External (XPRW, MethodObj)    // 2 Arguments

    Method (GPRW, 2, NotSerialized)
    {
        If (_OSI ("Darwin"))
        {
            If ((0x6D == Arg0))
            {
                Return (Package (0x02)
                {
                    0x6D,
                    Zero
                })
            }

            If ((0x0D == Arg0))
            {
                Return (Package (0x02)
                {
                    0x0D,
                    Zero
                })
            }
        }

        Return (XPRW (Arg0, Arg1))
    }
}
