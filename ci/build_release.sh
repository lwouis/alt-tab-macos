#!/usr/bin/env bash

set -exu

certificateFile="codesign"
keychain="alt-tab-macos.keychain"
keychainPassword="travis"

# create a keychain
security create-keychain -p $keychainPassword $keychain
# make keychain default so xcodebuild uses it
security default-keychain -s $keychain
# unlock keychain
security unlock-keychain -p $keychainPassword $keychain
# Recreate the certificate from the secure environment variable
echo "$APPLE_P12_CERTIFICATE" | base64 --decode > $certificateFile.p12
# import p12 into Keychain
security import $certificateFile.p12 -P "$APPLE_P12_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k $keychainPassword $keychain
# build release .app
xcodebuild CODE_SIGN_IDENTITY="Developer ID Application: Louis Pontoise (QXD7GW8FHY)"
