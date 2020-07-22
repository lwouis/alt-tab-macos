#!/usr/bin/env bash

set -exu

ownerName="alt-tab-macos"
appName="alt-tab-macos"
url="https://api.appcenter.ms/v0.1/apps/$ownerName/$appName"
version="$(cat $VERSION_FILE)"
symbolFile="$APP_NAME.app.dSYM"

function firstCall() {
  curl -X POST "$url/symbol_uploads" \
    -H "X-API-Token: $APPCENTER_TOKEN" \
    -H "accept: application/json" \
    -H "Content-Type: application/json" \
    -d "{ \"symbol_type\": \"Apple\", \"version\": \"$version\" }"
}

cd "$XCODE_BUILD_PATH"
ditto -c -k --keepParent "$symbolFile" "$symbolFile.zip"

c1="$(firstCall)"
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
