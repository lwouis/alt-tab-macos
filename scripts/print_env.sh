#!/usr/bin/env bash

set -ex

pwd
env | sort
jq --version
xcodebuild -version
xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -showBuildSettings | grep SWIFT_VERSION
