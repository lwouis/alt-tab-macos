#!/usr/bin/env bash

set -exu

version="$(cat "$VERSION_FILE")"
date="$(date +'%a, %d %b %Y %H:%M:%S %z')"
minimumSystemVersion="$(awk -F ' = ' '/MACOSX_DEPLOYMENT_TARGET/ { print $2; }' < config/base.xcconfig)"
zipName="$APP_NAME-$version.zip"
zipPath="$BUILD_DIR/$XCODE_BUILD_PATH/$zipName"
githubRepo="${GITHUB_REPOSITORY:-odrinateur/alt-alt-tab-macos}"
githubRefName="${GITHUB_REF_NAME:-master}"
releaseNotesUrl="https://github.com/${githubRepo}/blob/${githubRefName}/docs/changelog.md"
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  edSignatureAndLength="$(Pods/Sparkle/bin/sign_update -s "$SPARKLE_ED_PRIVATE_KEY" "$zipPath")"
else
  zipLength="$(wc -c < "$zipPath" | tr -d ' ')"
  edSignatureAndLength="length=\"${zipLength}\""
fi
echo "
    <item>
      <title>Version $version</title>
      <pubDate>$date</pubDate>
      <sparkle:minimumSystemVersion>$minimumSystemVersion</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$releaseNotesUrl</sparkle:releaseNotesLink>
      <enclosure
        url=\"https://github.com/${githubRepo}/releases/download/v$version/$zipName\"
        sparkle:version=\"$version\"
        sparkle:shortVersionString=\"$version\"
        $edSignatureAndLength
        type=\"application/octet-stream\"/>
    </item>
" > ITEM.txt
sed -i '' -e "/<\/language>/r ITEM.txt" docs/appcast.xml
cp docs/appcast.xml appcast.xml
