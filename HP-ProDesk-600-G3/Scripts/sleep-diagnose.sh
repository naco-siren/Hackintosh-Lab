#!/usr/bin/env bash
#
# Sleep / wake + iGPU display state on the ProDesk (Ventura).
# Best run over ssh *while the screen is dark after a failed wake*, so the live
# framebuffer/connector state is captured; can also be run after a forced reboot
# (then the logs of the previous boot / panic reports are what matter).
#
# Captures:
#   - pmset settings, assertions and the recent Sleep/Wake/DarkWake history
#   - iGPU framebuffers (AppleIntelFramebuffer@N): connector type, port, online/attached display
#   - SPDisplaysDataType
#   - kernel log of this boot and the previous one: WhateverGreen igfx, framebuffer, AGPM, wake
#   - injected PCIe ASPM properties; the previous sleep/wake failure code logged early in this boot
#   - newest panic report, if any (panic string decoded)
#
# Usage:   bash sleep-diagnose.sh
# Output:  ~/Desktop/sleep-diagnose-YYYYMMDD-HHMM.txt (+ ...-kernel-prev.txt: unfiltered kernel log before this boot)

set -uo pipefail
OUT="$HOME/Desktop/sleep-diagnose-$(date +%Y%m%d-%H%M).txt"

sec() { printf '\n===== %s =====\n' "$1"; }
KPRED='process == "kernel"'
KGREP='igfx|WhateverGreen|AppleIntelFramebuffer|AppleIntelKBL|AGPM|AppleGraphicsPowerManagement|IOFramebuffer|Display|Wake reason|wake from|PMRD|DarkWake|Sleep|panic|NVMe|Mausi|HID'
# Minutes of log before this boot to inspect (the sleep attempt); override: WINDOW=30 bash sleep-diagnose.sh
WINDOW=${WINDOW:-15}
FULL="${OUT%.txt}-kernel-prev.txt"

{
  sec "System"
  sw_vers; uname -a; uptime
  echo "boot-args: $(nvram boot-args 2>&1)"

  sec "pmset -g / custom / assertions"
  pmset -g
  pmset -g custom
  pmset -g assertions 2>&1 | head -60

  sec "pmset log: last Sleep / Wake / DarkWake / failures"
  pmset -g log 2>/dev/null | grep -E '^\S+ \S+ \S+ +(Sleep|Wake|DarkWake|Failure|Wake Requests|Kernel Idle sleep)' | tail -60

  sec "iGPU framebuffers (one per connector)"
  ioreg -l -w0 -r -c AppleIntelFramebuffer 2>/dev/null \
    | grep -E '\+-o AppleIntelFramebuffer|"connector-type"|"port-number"|"AAPL,display-alias"|"online"|"IOFBCurrentPixelCount"|"IOFBDisplayModeCount"|"started"|"IOFBTransform"|\+-o (AppleDisplay|IODisplayConnect|AppleBacklightDisplay)'
  echo "--- IGPU properties injected (ig-platform-id, force-online, framebuffer-*)"
  ioreg -l -w0 -r -n IGPU 2>/dev/null | grep -E '"(AAPL,ig-platform-id|force-online|framebuffer-[a-z-]+|device-id|model)"' | head -20

  sec "PCIe ASPM properties (pci-aspm-default injected / pci-aspm-custom applied)"
  ioreg -l -w0 2>/dev/null | grep -i -E '"pci-aspm-(default|custom)"' || echo "(none)"

  sec "SPDisplaysDataType"
  system_profiler SPDisplaysDataType 2>&1

  sec "Previous sleep/wake failure, as reported early in this boot (RTC trace point / powerd)"
  # Early-boot lines; the section below keeps only the last 300 matches and loses these.
  log show --last boot --style compact --predicate "$KPRED" 2>/dev/null \
    | grep -i -E 'failure|PMTrace|trace point|Sleep Wake|wake fail|sleep fail' | head -40
  pmset -g log 2>/dev/null | grep -i -E 'failure|Sleep Wake' | tail -20

  sec "Kernel log, current boot (framebuffer / WEG / wake)"
  log show --last boot --style compact --predicate "$KPRED" 2>/dev/null | grep -i -E "$KGREP" | tail -300

  sec "Kernel log, last $WINDOW min before this boot (the sleep attempt, after a forced reboot)"
  # kern.boottime -> "{ sec = 1762497000, usec = ... }"; take the $WINDOW minutes before it.
  # The unfiltered kernel log of that window goes to $FULL (DarkWake / full-wake attempts live there).
  BOOT=$(sysctl -n kern.boottime | sed -E 's/^\{ sec = ([0-9]+),.*/\1/')
  log show --style compact --predicate "$KPRED" \
    --start "$(date -r $((BOOT - WINDOW * 60)) '+%Y-%m-%d %H:%M:%S')" --end "$(date -r "$BOOT" '+%Y-%m-%d %H:%M:%S')" 2>/dev/null \
    | grep -v -i liludbg > "$FULL"
  grep -i -E "$KGREP" "$FULL" | tail -600

  sec "Panic reports"
  ls -lt /Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i -E 'panic|Sleep Wake' | head
  P=$(ls -t /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -1)
  # Ventura .panic: line 1 = JSON header, line 2 = JSON body whose "macOSPanicString" holds the text.
  [ -n "${P:-}" ] && { echo "--- $P"; sed -n 2p "$P" \
    | sed -E 's/.*"macOSPanicString":"//; s/"}[[:space:]]*$//; s/\\n/\
/g; s/\\t/  /g; s/\\"/"/g' | head -60; } || echo "(no .panic file)"
} > "$OUT" 2>&1

echo "written: $OUT ($(wc -l < "$OUT") lines)"
echo "written: $FULL ($(wc -l < "$FULL") lines)"
