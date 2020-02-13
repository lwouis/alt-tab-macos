#!/usr/bin/env bash

set -exu

version="$(cat $VERSION_FILE)"
# set the version in the app meta-data for the AppStore and app "Get Info" panel
sed -i '' -e "s/#VERSION#/$version/" Info.plist
