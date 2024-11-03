#!/usr/bin/env bash

set -ex

xcodebuild -version
xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -showBuildSettings | grep SWIFT_VERSION
xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -derivedDataPath DerivedData
file "$BUILD_DIR/$XCODE_BUILD_PATH/$APP_NAME.app/Contents/MacOS/$APP_NAME"
