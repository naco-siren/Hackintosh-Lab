# ⚠️ Read this before you copy this EFI

This EFI is for **HP ProDesk 600 G3 DM** with an **Apple BCM943224PCIEBT2** Wi-Fi/Bluetooth card, on **macOS 13 Ventura**.

## 1. 🛑 Sleep is broken

**Don't let this machine sleep while a DisplayPort monitor is plugged in.** Waking it up freezes the machine with a black screen. The only way out is to hold the power button.

Turn sleep off once, in Terminal:

```bash
sudo pmset -a sleep 0
```

The screen still turns off when idle, which works fine. Don't use  → Sleep, and don't short-press the power button.

If you really need sleep, unplug the DP cable before sleeping and plug it back in after it wakes.

## 2. It only works with this Wi-Fi card

Wi-Fi and Bluetooth only work with the card above (PCI ID `14e4:4353`). With any other card, or with no card, you get no Wi-Fi and no Bluetooth. Fixing that means changing the config entries tagged `[WLAN]`; see the machine [README](../../../README.md).

## 3. Add your own serial numbers first

The `config.plist` here ships with **blank SMBIOS** (serial, MLB, UUID, ROM). Fill in your own before you rely on iMessage or iCloud. Never copy someone else's.

## Which folder?

| Folder | Use it for |
|---|---|
| [`RELEASE/EFI`](RELEASE/EFI) | Daily use. Copy it to your USB stick's or disk's EFI partition. |
| [`DEBUG/EFI`](DEBUG/EFI) | Troubleshooting only: verbose boot, debug logs, slower. |

Everything else (what works, what was tried, how it was built) is in the machine [README](../../../README.md).
