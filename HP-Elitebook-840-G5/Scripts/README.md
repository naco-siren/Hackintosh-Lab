# Scripts (run on target Hackintosh in Big Sur)

Self-contained shell scripts to gather diagnostic data — and to apply
post-reinstall user-space tweaks — on a running macOS Big Sur on the
EliteBook 840 G5. Diagnostic scripts auto-bundle output into AirDrop-able
files on `~/Desktop`.

This folder also holds [`TESTING-PLAN.md`](TESTING-PLAN.md), the archived
iteration log (Iter 1–9). The scripts and the iteration log are paired:
each script's output text was the input to one or more iteration entries.

## Files

| File | Purpose | Typical timing |
|---|---|---|
| [`sleep-diagnose.sh`](sleep-diagnose.sh) | Apply non-EFI pmset sleep-friendly settings, do a guided lid-close test, capture pre/post pmset state + system log | After every EFI iteration that touches sleep |
| [`trackpad-diagnose.sh`](trackpad-diagnose.sh) | One-shot dump of IOReg / kextstat / USB / system log entries for trackpad investigation | Once after install, then again only if trackpad behavior changes |
| [`apply-trackpad-prefs.sh`](apply-trackpad-prefs.sh) | Re-apply the user-space trackpad defaults (scaling, 3-finger drag, click thresholds) that complement the Iter 9 I2C HID fix | After any macOS reinstall or `defaults` reset |
| [`TESTING-PLAN.md`](TESTING-PLAN.md) | Iteration log archive (Iter 1–9 narrative, hypothesis-revision history) | Read for historical context; do not extend unless reopening a workstream |

## How to run

1. AirDrop both `.sh` files (or the whole `Scripts/` folder)
   from your dev Mac to the Hackintosh.
2. On the Hackintosh, open Terminal:
   ```
   cd ~/Downloads/Scripts
   bash sleep-diagnose.sh        # interactive
   bash trackpad-diagnose.sh     # non-interactive, fast
   bash apply-trackpad-prefs.sh  # one-shot, then logout/relogin
   ```
3. The diagnostic scripts write to `~/Desktop/`. AirDrop the resulting
   `.zip` or `.txt` back to the dev Mac. `apply-trackpad-prefs.sh`
   produces no output file — it just writes user defaults.

`sleep-diagnose.sh` will:
- prompt for `sudo` once at the start
- list attached USB devices and pause for you to unplug nuisance
  ones (the ADATA stick is a known wake-source)
- apply: `womp=0 tcpkeepalive=0 networkoversleep=0 powernap=0
  hibernatemode=0 standby=0 autopoweroff=0`
- pause for you to close + open the lid
- capture `pmset -g log`, `pmset -g assertions`, `log show` entries
  filtered to sleep/wake events
- auto-zip to `~/Desktop/sleep-diagnose-YYYYMMDD-HHMM.zip`

`trackpad-diagnose.sh` is non-interactive, just dumps everything
trackpad-related to a single `.txt` file.
