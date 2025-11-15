#!/usr/bin/env bash

set -ex

xcodebuild -version
xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -showBuildSettings | grep SWIFT_VERSION

set -o pipefail && xcodebuild test -workspace alt-tab-macos.xcworkspace -scheme Test -configuration Release | scripts/xcbeautify
