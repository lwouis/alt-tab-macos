#!/usr/bin/env bash

set -ex

xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -derivedDataPath DerivedData
file "$BUILD_DIR/$XCODE_BUILD_PATH/$APP_NAME.app/Contents/MacOS/$APP_NAME"
