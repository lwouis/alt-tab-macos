#!/usr/bin/env bash

set -exu

certificateFile="codesign"
certificatePassword=$(openssl rand -base64 12)

scripts/codesign/generate_selfsigned_certificate.sh "$certificateFile" "$certificatePassword"
scripts/codesign/import_certificate_into_new_keychain.sh "$certificateFile" "$certificatePassword"
