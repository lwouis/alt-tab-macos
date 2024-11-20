#!/usr/bin/env bash

set -ex

xcodebuild -version
xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -showBuildSettings | grep SWIFT_VERSION

xcodebuild test -workspace alt-tab-macos.xcworkspace -scheme Test
