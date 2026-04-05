#!/usr/bin/env bash

set -exu

ownerName="alt-tab-macos"
appName="alt-tab-macos"
url="https://api.appcenter.ms/v0.1/apps/$ownerName/$appName"
version="$(cat "$VERSION_FILE")"

# Upload a single .dSYM bundle to AppCenter (zip, request slot, PUT to blob, mark committed).
# Called once per dSYM produced by the Release build:
#   - AltTab.app.dSYM        host binary + everything statically linked (AppCenter, AppCenterCrashes, ShortcutRecorder)
#   - Sparkle.framework.dSYM Sparkle is the only .dynamic SPM product, so it has its own dSYM
# CrashReporter.xcframework ships without dSYMs (PLCrashReporter is binary-only); AppCenter has
# server-side symbols for it.
function upload_dsym() {
  local symbolFile="$1"
  ditto -c -k --keepParent "$symbolFile" "$symbolFile.zip"

  local c1 symbol_upload_id upload_url
  c1="$(curl -X POST "$url/symbol_uploads" \
    -H "X-API-Token: $APPCENTER_TOKEN" \
    -H "accept: application/json" \
    -H "Content-Type: application/json" \
    -d "{ \"symbol_type\": \"Apple\", \"version\": \"$version\" }")"
  symbol_upload_id="$(jq -r '.symbol_upload_id' <<<"$c1")"
  upload_url="$(jq -r '.upload_url' <<<"$c1")"

  curl -X PUT "$upload_url" \
    -H "x-ms-blob-type: BlockBlob" \
    --upload-file "$symbolFile.zip"

  curl -X PATCH "$url/symbol_uploads/$symbol_upload_id" \
    -H "X-API-Token: $APPCENTER_TOKEN" \
    -H "accept: application/json" \
    -H "Content-Type: application/json" \
    -d '{ "status": "committed" }'
}

cd "$XCODE_BUILD_PATH"
upload_dsym "$APP_NAME.app.dSYM"
upload_dsym "Sparkle.framework.dSYM"
