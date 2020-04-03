#!/usr/bin/env bash

set -exu

certificateFile="$1"
certificatePassword="$2"

# import p12 into Keychain
security import $certificateFile.p12 -P $certificatePassword -T /usr/bin/codesign
# in Keychain, set Trust > Code Signing > "Always Trust"
security add-trusted-cert -d -r trustRoot -p codeSign $certificateFile.crt
