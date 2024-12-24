#!/usr/bin/env bash

set -exu

# needed because of macOS SIP (see https://stackoverflow.com/a/35570229)
export DYLD_LIBRARY_PATH="$MAGICK_HOME/lib"

currentDir="$(pwd)"
finalSize=256
upscaledSize=$((finalSize * 4))

function generate_png() {
  /Applications/Inkscape.app/Contents/MacOS/inkscape \
    -w "$upscaledSize" -h "$upscaledSize" \
    "$currentDir/$1.svg" \
    -o "$currentDir/$1_$upscaledSize.png"

  # better quality if we make a large png, then downscale it, then produce the small png directly
  magick \
    "$currentDir/$1_$upscaledSize.png" \
    -resize 25% \
    "$currentDir/$1_$finalSize.png"
}

generate_png "resources/icons/app/app"
