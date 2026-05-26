#!/usr/bin/env bash

set -exu

version="$(cat "$VERSION_FILE")"
githubRepo="${GITHUB_REPOSITORY:-odrinateur/alt-alt-tab-macos}"
downloadUrl="https://github.com/${githubRepo}/releases/download/v${version}/${APP_NAME}-${version}.zip"
sed -i "" -E "s|https://github.com/[^/]+/[^/]+/releases/download/v[^/]+/[^\"]+|${downloadUrl}|g" README.md
