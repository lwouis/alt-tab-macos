#!/usr/bin/env bash

set -exu

version="$(cat "$VERSION_FILE")"
appFile="$APP_NAME.app"
zipName="$APP_NAME-$version.zip"
cd "$XCODE_BUILD_PATH"
ditto -c -k --keepParent "$appFile" "$zipName"
shasum -a 256 "$zipName"
