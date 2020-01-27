#!/usr/bin/env bash

set -exu

appName="AltTab"
version="$(cat VERSION.txt)"
appFile="$appName.app"
zipName="$appName-$version.zip"

cd build/Release
mv "alt-tab-macos.app" "$appFile"
ditto -c -k --keepParent "$appFile" "$zipName"

# request notarization
requestUUID=$(xcrun altool \
  --notarize-app \
  --primary-bundle-id "com.lwouis.alt-tab-macos" \
  --username "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --file "$zipName" 2>&1 |
  awk '/RequestUUID/ { print $NF; }')
if [[ $requestUUID == "" ]]; then exit 1; fi

# poll notarization status until done
request_status="in progress"
while [[ "$request_status" == "in progress" ]]; do
  sleep 10
  request_status=$(xcrun altool \
    --notarization-info "$requestUUID" \
    --username "$APPLE_ID" \
    --password "$APPLE_PASSWORD" 2>&1 |
    awk -F ': ' '/Status:/ { print $2; }')
  echo "notarization status: $request_status"
done
if [[ $request_status != "success" ]]; then exit 1; fi

# staple build
xcrun stapler staple "$appFile"
ditto -c -k --keepParent "$appFile" "$zipName"
