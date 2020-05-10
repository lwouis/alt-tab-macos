#!/usr/bin/env bash

set -exu

version="$(cat $VERSION_FILE)"
date="$(date +'%a, %d %b %Y %H:%M:%S %z')"
minimumSystemVersion="$(awk -F ' = ' '/MACOSX_DEPLOYMENT_TARGET/ { print $2; }' < config/base.xcconfig)"
zipName="$APP_NAME-$version.zip"
edSignatureAndLength=$(Pods/Sparkle/bin/sign_update -s $SPARKLE_ED_PRIVATE_KEY "$XCODE_BUILD_PATH/$zipName")

echo "
    <item>
      <title>Version $version</title>
      <pubDate>$date</pubDate>
      <sparkle:minimumSystemVersion>$minimumSystemVersion</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://alt-tab-macos.netlify.app/changelog-bare</sparkle:releaseNotesLink>
      <enclosure
        url=\"https://github.com/lwouis/alt-tab-macos/releases/download/v$version/$zipName\"
        sparkle:version=\"$version\"
        sparkle:shortVersionString=\"$version\"
        $edSignatureAndLength
        type=\"application/octet-stream\"/>
    </item>
" > ITEM.txt

sed -i '' -e "/<\/language>/r ITEM.txt" appcast.xml
