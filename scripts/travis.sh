#!/usr/bin/env bash

set -exu

env | sort
npm ci
npx commitlint-travis
if [ $IS_RELEASE ]; then
  scripts/determine_version_and_changelog.sh
  scripts/replace_environment_variables_in_app.sh
fi
pod install
if [ $IS_RELEASE ]; then
  scripts/codesign/setup_ci_master.sh
  xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -derivedDataPath DerivedData
  scripts/package_and_notarize_release.sh
  scripts/update_appcast.sh
  npx semantic-release
else
  scripts/codesign/setup_ci_pr.sh
  xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Debug -derivedDataPath DerivedData
fi
