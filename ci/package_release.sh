#!/usr/bin/env bash

set -ex

appName="AltTab"
version="$(cat VERSION.txt)"

cd build/Release
mv "alt-tab-macos.app" "$appName.app"
zip -r "$appName-$version.zip" "$appName.app"
tar czf "$appName-$version.tar.gz" "$appName.app"
