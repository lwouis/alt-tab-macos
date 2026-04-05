#!/usr/bin/env bash
# Batch-encode PNG/JPEG → HEIC at the chosen quality and longest-edge size.
#
# Defaults: longest edge 1000px, quality 50. q50 was chosen as the AltTab baseline
# after side-by-side comparison at q20/q35/q50/q65/q80 — it's the lowest setting
# where text in screenshot illustrations stayed legible and gradient backgrounds
# didn't band, at roughly 50% of the bytes of q80.
#
# Usage:
#   bash scripts/assets/encode_heic.sh <source_dir> [longest_edge] [quality] [output_dir]
#
# Examples:
#   bash scripts/assets/encode_heic.sh ~/Desktop
#   bash scripts/assets/encode_heic.sh ~/Desktop 1000 50
#   bash scripts/assets/encode_heic.sh ~/Desktop 1000 60 /tmp/heic-q60
#
# After running, MANUALLY review a representative sample by decoding a HEIC back
# to PNG and comparing against its source:
#   sips -s format png /tmp/heic-out/sample.heic --out /tmp/sample.png
#   open /tmp/sample.png ~/Desktop/sample.png
#
# If quality is unacceptable, bump to q60 or q65 and re-run.

set -euo pipefail

SRC="${1:?Source directory required}"
LONGEST_EDGE="${2:-1000}"
QUALITY="${3:-50}"
OUT="${4:-/tmp/heic-out}"

if [[ ! -d "$SRC" ]]; then
    echo "Source directory does not exist: $SRC" >&2
    exit 1
fi

mkdir -p "$OUT"

count=0
total_in=0
total_out=0

shopt -s nullglob nocaseglob
for f in "$SRC"/*.png "$SRC"/*.jpg "$SRC"/*.jpeg; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    base="${name%.*}"
    out_path="$OUT/${base}.heic"

    in_size=$(stat -f%z "$f")
    sips -Z "$LONGEST_EDGE" -s format heic -s formatOptions "$QUALITY" "$f" --out "$out_path" >/dev/null 2>&1
    out_size=$(stat -f%z "$out_path")

    pct=$(( (in_size - out_size) * 100 / in_size ))
    printf "  %-60s %8d → %6d B  (-%d%%)\n" "$name" "$in_size" "$out_size" "$pct"

    count=$((count + 1))
    total_in=$((total_in + in_size))
    total_out=$((total_out + out_size))
done
shopt -u nullglob nocaseglob

if (( count == 0 )); then
    echo "No PNG/JPEG files found in $SRC"
    exit 1
fi

saved=$((total_in - total_out))
overall_pct=$(( saved * 100 / total_in ))
echo ""
echo "Processed $count file(s): $total_in → $total_out B (saved $saved B = $overall_pct%)"
echo "Output: $OUT"
echo ""
echo "Now visually review a sample. Pick the file with the most text or strongest gradients:"
echo "  sips -s format png $OUT/<sample>.heic --out /tmp/sample-decoded.png"
echo "  open /tmp/sample-decoded.png $SRC/<sample>.png"
