# ⚠️ Read this before you copy this EFI

This EFI is for **HP EliteBook 840 G5** with a **Broadcom BCM94352Z** Wi-Fi/Bluetooth card, on **macOS 11 Big Sur**.

## 1. It only works with this Wi-Fi card

The 840 G5 ships with an **Intel 8265**, and this EFI does **not** support it. Wi-Fi and Bluetooth here only work with a BCM94352Z (Wi-Fi `14e4:43b1`, BT `0489:e07a`). For any other card, change the entries listed under `#Hardware` → `WLAN-coupled` in `config.plist`. The machine [README](../../../README.md), section "BT card decision matrix", covers the alternatives.

## 2. Big Sur is end-of-life

Big Sur hasn't had security updates since 2023-09. For an OS that still gets updates, use [`../../12/BCM94352z/`](../../12/BCM94352z/), which covers Monterey and Ventura.

## 3. Add your own serial numbers first

Put your own SMBIOS (serial, MLB, UUID, ROM) into `config.plist` → `PlatformInfo` → `Generic` before first boot. Never use someone else's.

## Which folder?

| Folder | Use it for |
|---|---|
| [`RELEASE/EFI`](RELEASE/EFI) | Daily use |
| [`DEBUG/EFI`](DEBUG/EFI) | Troubleshooting only: verbose boot, debug logs |
