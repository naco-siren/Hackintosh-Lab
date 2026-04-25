/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20260408 (64-bit version)
 * Copyright (c) 2000 - 2026 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of SSDT-DISABLE-FP.aml
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x00000074 (116)
 *     Revision         0x02
 *     Checksum         0x96
 *     OEM ID           "OCEFI "
 *     OEM Table ID     "DISFP"
 *     OEM Revision     0x00001000 (4096)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20260408 (539362312)
 */
DefinitionBlock ("", "SSDT", 2, "OCEFI ", "DISFP", 0x00001000)
{
    External (_SB_.PCI0.XHC_.RHUB.HS07, DeviceObj)

    Scope (\_SB.PCI0.XHC.RHUB.HS07)
    {
        Method (_STA, 0, NotSerialized)  // _STA: Status
        {
            If (_OSI ("Darwin"))
            {
                Return (Zero)
            }

            Return (0x0F)
        }
    }
}

