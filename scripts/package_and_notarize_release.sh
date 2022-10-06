#!/usr/bin/env bash

set -exu

version="$(cat $VERSION_FILE)"
appFile="$APP_NAME.app"
zipName="$APP_NAME-$version.zip"
bundleId="$(awk -F ' = ' '/PRODUCT_BUNDLE_IDENTIFIER/ { print $2; }' < config/base.xcconfig)"

cd "$XCODE_BUILD_PATH"
ditto -c -k --keepParent "$appFile" "$zipName"

# request notarization
requestUuid=$(xcrun altool \
  --notarize-app \
  --primary-bundle-id "$bundleId" \
  --username "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --file "$zipName" 2>&1 |
  tee /dev/tty |
  awk '/RequestUUID/ { print $NF;exit; }')
if [[ $requestUuid == "" ]]; then exit 1; fi

# poll notarization status until success/invalid, or 15min have passed
requestStatus="in progress"
timeoutCounter=0
until [[ "$requestStatus" == "success" ]] || [[ "$requestStatus" == "invalid" ]] || [[ $timeoutCounter -eq 1500 ]]; do
  sleep 10
  timeoutCounter=$((timeoutCounter+10))
  set +e
  requestLogs=$(xcrun altool \
    --notarization-info "$requestUuid" \
    --username "$APPLE_ID" \
    --password "$APPLE_PASSWORD" 2>&1)
  set -e
  requestStatus=$(echo "$requestLogs" | awk -F ': ' '/Status:/ { print $2; }')
done
if [[ $requestStatus != "success" ]]; then
  echo "$requestLogs" | awk -F ': ' '/LogFileURL:/ { print $2; }' | xargs curl
  exit 1
fi

# staple build
xcrun stapler staple "$appFile"
ditto -c -k --keepParent "$appFile" "$zipName"
