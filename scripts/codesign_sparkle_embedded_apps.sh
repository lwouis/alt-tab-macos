#!/usr/bin/env bash

# set to empty for debug builds
OTHER_CODE_SIGN_FLAGS="${OTHER_CODE_SIGN_FLAGS:-}"

set -exu

# codesign --deep is only 1 level deep. It misses Sparkle embedded app AutoUpdate
# this build phase script works around the issue

codesign --verbose --force --sign "$CODE_SIGN_IDENTITY" $OTHER_CODE_SIGN_FLAGS "${CODESIGNING_FOLDER_PATH}/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/Autoupdate.app"
