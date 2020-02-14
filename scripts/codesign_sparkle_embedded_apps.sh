#!/usr/bin/env bash

set -exu

# codesign --deep is only 1 level deep. It misses Sparkle embedded app AutoUpdate
# this build phase script works around the issue

if [[ "$CONFIGURATION" == "Release" ]]; then
  codesign --verbose --force --sign "$CODE_SIGN_IDENTITY" $OTHER_CODE_SIGN_FLAGS "${PODS_ROOT}/Sparkle/Sparkle.framework/Resources/Autoupdate.app"
fi
