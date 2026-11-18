#!/usr/bin/env bash
# Render the DevOS Plymouth theme images (SRS BOOT-010).
#
# Sources:  boot/grub/themes/devos/logo.png  (the rendered DevOS logo, shared with GRUB)
#           boot/plymouth/devos/devos.script, devos.plymouth (hand-written)
# Output:   boot/plymouth/devos/*.png  (committed, so builds need no render tools)
#
# Requires: imagemagick (magick).
# Usage:    scripts/render-plymouth-theme.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/boot/plymouth/devos"
command -v magick >/dev/null || { echo "missing: magick" >&2; exit 1; }

cp "$ROOT/boot/grub/themes/devos/logo.png" "$OUT/logo.png"

# Progress bar: 240x4 track, accent gradient fill (same accent as the logo).
magick -size 240x4 xc:none -fill 'rgba(255,255,255,0.08)' \
    -draw 'roundrectangle 0,0 239,3 2,2' PNG32:"$OUT/track.png"
magick -size 4x240 gradient:'#2DD4BF-#8B5CF6' -rotate -90 \
    \( -size 240x4 xc:none -fill white -draw 'roundrectangle 0,0 239,3 2,2' \) \
    -compose copy_opacity -composite PNG32:"$OUT/fill.png"

# Password entry: the login screen's field (12 px radius, faint border).
magick -size 344x46 xc:none -fill 'rgba(255,255,255,0.05)' -stroke 'rgba(255,255,255,0.12)' \
    -strokewidth 1 -draw 'roundrectangle 0.5,0.5 343.5,45.5 12,12' PNG32:"$OUT/entry.png"
magick -size 10x10 xc:none -fill '#E6EDF7' -draw 'circle 5,5 5,1' PNG32:"$OUT/bullet.png"

echo "rendered into $OUT"
