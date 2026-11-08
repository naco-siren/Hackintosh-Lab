# ⚠️ Read this before you copy this EFI

This EFI is for **HP EliteBook 840 G5** with a **Broadcom BCM94352Z** Wi-Fi/Bluetooth card, on **macOS 12 Monterey and 13 Ventura**. The same EFI covers both.

## 1. It only works with this Wi-Fi card

The 840 G5 ships with an **Intel 8265**, and this EFI does **not** support it. Wi-Fi and Bluetooth here only work with a BCM94352Z (Wi-Fi `14e4:43b1`, BT `0489:e07a`). For any other card, change the entries listed under `#Hardware` → `WLAN-coupled` in `config.plist`. The machine [README](../../../README.md), section "BT card decision matrix", covers the alternatives.

## 2. Don't upgrade past Ventura

Sonoma (14) and later remove the stock driver this card's Wi-Fi uses. This EFI has no workaround for that, so Wi-Fi stops working. See [`../../13/README.md`](../../13/README.md).

## 3. Add your own serial numbers first

Put your own SMBIOS (serial, MLB, UUID, ROM) into `config.plist` → `PlatformInfo` → `Generic` before first boot. Never use someone else's.

## Which folder?

| Folder | Use it for |
|---|---|
| [`RELEASE/EFI`](RELEASE/EFI) | Daily use |
| [`DEBUG/EFI`](DEBUG/EFI) | Troubleshooting only: verbose boot, debug logs |
