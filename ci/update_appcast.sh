#!/usr/bin/env bash

set -exu

version="$(cat VERSION.txt)"
changelogDelta="$(npx marked < CHANGELOG_DELTA.txt)"
date="$(date +'%a, %d %b %Y %H:%M:%S %z')"
minimumSystemVersion="$(sed -En 's/MACOSX_DEPLOYMENT_TARGET = (.+);/\1/p' alt-tab-macos.xcodeproj/project.pbxproj | head -n 1 | awk '{$1=$1};1')"
version="$(cat VERSION.txt)"
zipName="AltTab-$version.zip"
edSignatureAndLength=$(Pods/Sparkle/bin/sign_update -s $SPARKLE_ED_PRIVATE_KEY "build/Release/$zipName")

echo "
    <item>
      <title>Version $version</title>
      <pubDate>$date</pubDate>
      <sparkle:minimumSystemVersion>$minimumSystemVersion</sparkle:minimumSystemVersion>
      <description><![CDATA[
$changelogDelta
      ]]>
      </description>
      <enclosure
        url=\"https://github.com/lwouis/alt-tab-macos/releases/download/v$version/$zipName\"
        sparkle:version=\"$version\"
        sparkle:shortVersionString=\"$version\"
        $edSignatureAndLength
        type=\"application/octet-stream\"/>
    </item>
" > ITEM.txt

sed -i '' -e "/<\/language>/r ITEM.txt" appcast.xml
