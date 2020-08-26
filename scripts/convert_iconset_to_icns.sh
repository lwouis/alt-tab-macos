#!/usr/bin/env bash

set -exu

# xcode or iconutil re-encode PNGs, increasing the final .icns file for no reason; we use a third-party tool instead
# see https://github.com/lwouis/createicns
scripts/createicns resources/icons/app/app.iconset
mv app.icns resources/icons/app/app.icns
