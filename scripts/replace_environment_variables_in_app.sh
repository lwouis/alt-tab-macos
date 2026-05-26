#!/usr/bin/env bash

set -exu

version="$(cat "$VERSION_FILE")"
githubRepo="${GITHUB_REPOSITORY:-odrinateur/alt-alt-tab-macos}"
githubRefName="${GITHUB_REF_NAME:-master}"
feedUrl="https://raw.githubusercontent.com/${githubRepo}/${githubRefName}/appcast.xml"
sed -i '' -e "s/#VERSION#/$version/g" Info.plist
sed -i '' -e "s|#SUFeedURL#|$feedUrl|g" Info.plist
sparklePublicKey="${SPARKLE_PUBLIC_KEY:-}"
sed -i '' -e "s/#SPARKLE_PUBLIC_KEY#/$sparklePublicKey/g" Info.plist
