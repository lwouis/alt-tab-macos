#!/usr/bin/env bash

set -exu

version="$(cat $VERSION_FILE)"

sed -i '' -e "s/#VERSION#/$version/" Info.plist
sed -i '' -e "s/#FEEDBACK_TOKEN#/$FEEDBACK_TOKEN/" Info.plist
sed -i '' -e "s/#APPCENTER_SECRET#/$APPCENTER_SECRET/" Info.plist
