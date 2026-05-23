#!/usr/bin/env bash

# Builds a Release binary and packages it into a DMG installer.
# Usage: scripts/create_dmg.sh [--skip-build]

set -euo pipefail

APP_NAME="${APP_NAME:-AltTab-SwiftUI}"
BUILD_DIR="${BUILD_DIR:-$(pwd)}"
XCODE_BUILD_PATH="${XCODE_BUILD_PATH:-DerivedData/Build/Products/Release}"
app_path="$BUILD_DIR/$XCODE_BUILD_PATH/$APP_NAME.app"

# ── Build ──────────────────────────────────────────────────────────────
if [[ "${1:-}" != "--skip-build" ]]; then
  echo "==> Building Release…"
  set -o pipefail && xcodebuild \
    -project alt-tab-macos.xcodeproj \
    -scheme Release \
    -configuration Release \
    -derivedDataPath DerivedData \
    | tail -3
  if [[ ! -d "$app_path" ]]; then
    echo "Error: Build succeeded but $app_path not found." >&2
    exit 1
  fi
fi

if [[ ! -d "$app_path" ]]; then
  echo "Error: $app_path not found. Run without --skip-build first." >&2
  exit 1
fi

# ── Package DMG ────────────────────────────────────────────────────────
echo "==> Packaging DMG…"

version="$(defaults read "$app_path/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.0.1")"
dmg_name="$APP_NAME-$version"
final_dmg="$BUILD_DIR/$dmg_name.dmg"

rm -f "$final_dmg"

# Create a temporary folder with app + Applications symlink
stage="/tmp/$dmg_name-staging"
rm -rf "$stage"
mkdir -p "$stage"
cp -R "$app_path" "$stage/"
ln -s /Applications "$stage/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$stage" \
  -ov \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$final_dmg"

rm -rf "$stage"

echo "==> Created: $final_dmg ($(du -sh "$final_dmg" | cut -f1))"
