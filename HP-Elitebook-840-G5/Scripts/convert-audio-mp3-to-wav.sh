#!/usr/bin/env bash
#
# Convert OpenCore EFI audio resources from .mp3 to 16-bit PCM .wav,
# in place inside an OC Resources/Audio/ directory.
#
# Why: codecs that only expose 16/24-bit PCM (e.g. Conexant CX8200 on
# the HP EliteBook 840 G5) reject the 32-bit float PCM that OpenCore's
# built-in MP3 decoder produces, so PlayFile setup returns
# EFI_UNSUPPORTED. Pre-decoding the chime/voice audio to 16-bit WAV
# bypasses the MP3 decode path entirely — AudioDxe just passes the raw
# PCM straight to the codec's DAC, which is exactly what 16/24-bit
# codecs are happy to consume.
#
# Behavior:
#   * Each <name>.mp3 in <Audio dir> becomes <name>.wav at 48 kHz /
#     stereo / signed 16-bit little-endian PCM (CX8200's most-supported
#     format; works on every modern HDA codec).
#   * Originals are moved to /tmp/oc-mp3-backup-<TIMESTAMP>/ unless
#     --keep-mp3 is passed. Moving them out of Audio/ matters because
#     OpenCore's lookup order between same-basename .mp3/.wav is not
#     guaranteed across versions; removing the .mp3 forces the .wav.
#   * Idempotent on rerun: if <name>.wav already exists the .mp3 is
#     simply moved/skipped.
#
# Usage:
#   bash Scripts/convert-audio-mp3-to-wav.sh <Audio dir> [--keep-mp3]
#
# Requires: ffmpeg in PATH (basic build is fine — mp3 demuxer + pcm_s16le
# encoder are in every standard ffmpeg, no ffmpeg-full required).

set -euo pipefail

usage() {
    cat >&2 <<EOF
usage: $0 <Audio dir> [--keep-mp3]

  <Audio dir>   path to OpenCore EFI/OC/Resources/Audio
  --keep-mp3    convert side-by-side, leave .mp3 in place
                (default: move .mp3 to /tmp/oc-mp3-backup-<TS>/)
EOF
    exit 1
}

[[ $# -lt 1 || "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage
AUDIO_DIR="$1"
KEEP_MP3=0
[[ "${2:-}" == "--keep-mp3" ]] && KEEP_MP3=1

[[ -d "$AUDIO_DIR" ]] || { echo "error: '$AUDIO_DIR' is not a directory" >&2; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo "error: ffmpeg not in PATH" >&2; exit 1; }

shopt -s nullglob
mp3_files=("$AUDIO_DIR"/*.mp3)
if [[ ${#mp3_files[@]} -eq 0 ]]; then
    echo "no .mp3 files in $AUDIO_DIR — nothing to do"
    exit 0
fi

backup_dir=""
if [[ $KEEP_MP3 -eq 0 ]]; then
    backup_dir="/tmp/oc-mp3-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
fi

converted=0
skipped=0
for mp3 in "${mp3_files[@]}"; do
    base=$(basename "$mp3" .mp3)
    wav="$AUDIO_DIR/$base.wav"

    if [[ -f "$wav" ]]; then
        printf "  skip  %s.wav already exists\n" "$base"
        skipped=$((skipped + 1))
    else
        # 16-bit signed little-endian PCM, 48 kHz, stereo.
        # AudioDxe + CX8200 (and every HDA codec) accept this directly.
        if ! ffmpeg -hide_banner -loglevel error -y \
            -i "$mp3" \
            -ar 48000 -ac 2 -sample_fmt s16 -acodec pcm_s16le \
            "$wav" 2>&1; then
            echo "error: ffmpeg failed on $mp3" >&2
            exit 1
        fi
        size=$(stat -f %z "$wav" 2>/dev/null || stat -c %s "$wav")
        printf "  conv  %s.mp3 -> %s.wav (%s bytes)\n" "$base" "$base" "$size"
        converted=$((converted + 1))
    fi

    if [[ $KEEP_MP3 -eq 0 ]]; then
        mv "$mp3" "$backup_dir/"
    fi
done

echo
echo "summary: $converted converted, $skipped skipped (.wav already existed)"
if [[ $KEEP_MP3 -eq 0 ]]; then
    echo "originals moved to: $backup_dir"
    echo "revert with:"
    echo "  mv \"$backup_dir\"/*.mp3 \"$AUDIO_DIR/\" && rm -rf \"$AUDIO_DIR\"/*.wav"
fi
