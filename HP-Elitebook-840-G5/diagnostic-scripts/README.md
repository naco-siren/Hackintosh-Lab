# Diagnostic scripts (run on target Hackintosh in Big Sur)

Self-contained shell scripts to gather diagnostic data from a running
macOS Big Sur on the EliteBook 840 G5. They auto-bundle output
into AirDrop-able files on `~/Desktop`.

## Files

| Script | Purpose | Typical timing |
|---|---|---|
| [`sleep-diagnose.sh`](sleep-diagnose.sh) | Apply non-EFI pmset sleep-friendly settings, do a guided lid-close test, capture pre/post pmset state + system log | After every EFI iteration that touches sleep |
| [`trackpad-diagnose.sh`](trackpad-diagnose.sh) | One-shot dump of IOReg / kextstat / USB / system log entries for trackpad investigation | Once after install, then again only if trackpad behavior changes |

## How to run

1. AirDrop both `.sh` files (or the whole `diagnostic-scripts/` folder)
   from your dev Mac to the Hackintosh.
2. On the Hackintosh, open Terminal:
   ```
   cd ~/Downloads/diagnostic-scripts
   bash sleep-diagnose.sh        # interactive
   bash trackpad-diagnose.sh     # non-interactive, fast
   ```
3. The scripts write to `~/Desktop/`. AirDrop the resulting `.zip`
   or `.txt` back to the dev Mac.

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
