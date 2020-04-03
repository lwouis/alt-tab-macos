#!/usr/bin/env bash

set -exu

certificateFile="$1"
certificatePassword="$2"

keychain="alt-tab-macos.keychain"
keychainPassword="travis"

# create a keychain
security create-keychain -p $keychainPassword $keychain
# make keychain default so xcodebuild uses it
security default-keychain -s $keychain
# unlock keychain
security unlock-keychain -p $keychainPassword $keychain
# import p12 into Keychain
security import $certificateFile.p12 -P "$certificatePassword" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k $keychainPassword $keychain
