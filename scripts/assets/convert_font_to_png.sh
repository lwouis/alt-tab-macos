#!/usr/bin/env bash

set -exu

# needed because of macOS SIP (see https://stackoverflow.com/a/35570229)
export DYLD_LIBRARY_PATH="$MAGICK_HOME/lib"

function convert() {
  magick convert \
    -fill black \
    -gravity center \
    -font "resources/SF-Pro-Text-Regular-Full.otf" \
    -size 64x64 \
    -pointsize $3 \
    -draw "text $4 '$1'" \
    xc:none \
    "resources/icons/tabs/$2@2x.png"
}

convert "􀜊" "general" "60" "-3,0"
convert "􀆔" "controls" "54" "-3,0"
convert "􀝥" "appearance" "52" "-2,0"
convert "􀖀" "policies" "58" "-2,0"
convert "􀉻" "blacklists" "58" "-5,1"
convert "􀅴" "about" "58" "-2,0"
convert "􀉿" "acknowledgments" "53" "-2,0"
