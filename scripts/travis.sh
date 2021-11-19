#!/usr/bin/env bash

set -exu

env | sort

npm ci

npx commitlint-travis
scripts/ensure_generated_files_are_up_to_date.sh

if [ $IS_RELEASE ]; then
  scripts/determine_version.sh
  scripts/replace_environment_variables_in_app.sh
fi

scripts/codesign/setup_ci_master.sh
xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -derivedDataPath DerivedData
file "$TRAVIS_BUILD_DIR/$XCODE_BUILD_PATH/$APP_NAME.app/Contents/MacOS/$APP_NAME"

if [ $IS_RELEASE ]; then
  scripts/package_and_notarize_release.sh
  scripts/upload_symbols_to_appcenter.sh
  scripts/update_appcast.sh
  npx semantic-release
  scripts/update_website.sh
fi
