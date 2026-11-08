# Hackintosh-Lab

OpenCore EFIs for specific machines. **Every EFI here is built for one machine *and* one Wi-Fi/Bluetooth card.** Use one only if both match your hardware, and read its known issues first.

| Machine | WLAN card (required) | macOS | EFI | ⚠️ Known issues |
|---|---|---|---|---|
| HP EliteBook 840 G5 | Broadcom **BCM94352Z** (`14e4:43b1`) — not the stock Intel 8265 | 11 Big Sur | [`HP-Elitebook-840-G5/EFIs/11/BCM94352z/`](HP-Elitebook-840-G5/EFIs/11/BCM94352z/) | Big Sur is EOL |
| HP EliteBook 840 G5 | Broadcom **BCM94352Z** (`14e4:43b1`) — not the stock Intel 8265 | 12 Monterey, 13 Ventura | [`HP-Elitebook-840-G5/EFIs/12/BCM94352z/`](HP-Elitebook-840-G5/EFIs/12/BCM94352z/) | — |
| HP ProDesk 600 G3 DM | Apple **BCM943224PCIEBT2** (`14e4:4353`) | 13 Ventura | [`HP-ProDesk-600-G3/EFIs/13/BCM943224PCIEBT2/`](HP-ProDesk-600-G3/EFIs/13/BCM943224PCIEBT2/) | 🛑 **Sleep broken**: waking with a DP monitor attached freezes the machine. Disable sleep. |

Before you use any of them:

1. **SMBIOS is blank.** Generate your own serial, MLB, UUID and ROM; never reuse someone else's.
2. **Different Wi-Fi card?** Each `config.plist` has a `#Hardware` key (OpenCore ignores it) that lists the entries that exist only for the card above. Remove or replace those for your card.
3. **RELEASE** is for daily use. **DEBUG** is for troubleshooting.

Per-machine details: [EliteBook 840 G5](HP-Elitebook-840-G5/README.md) · [ProDesk 600 G3 DM](HP-ProDesk-600-G3/README.md)
