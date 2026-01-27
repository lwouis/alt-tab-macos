#!/usr/bin/env bash

set -e

# Install script for local AltTab.app builds
# Usage: ./scripts/install_local_build.sh [Debug|Release] [--launch|-l]
# Default: Debug
# Options:
#   --launch, -l: Automatically launch after install (no prompt)

BUILD_CONFIG="${1:-Debug}"
AUTO_LAUNCH=false

# Check for launch flag
for arg in "$@"; do
    if [[ "$arg" == "--launch" || "$arg" == "-l" ]]; then
        AUTO_LAUNCH=true
    fi
done

APP_NAME="AltTab"
TARGET_APP="/Applications/${APP_NAME}.app"

echo "📦 Installing ${BUILD_CONFIG} build of ${APP_NAME}..."

# Find the built app in DerivedData (prefer Build/Products over Index.noindex)
BUILD_APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Build/Products/${BUILD_CONFIG}/${APP_NAME}.app" -type d 2>/dev/null | grep -v "Index.noindex" | head -1)

if [ -z "$BUILD_APP" ]; then
    echo "❌ Error: Could not find ${APP_NAME}.app in DerivedData"
    echo "   Please build the project first in Xcode:"
    echo "   - Debug build: Cmd+B"
    echo "   - Release build: Product > Build For > Running"
    exit 1
fi

echo "✅ Found: $BUILD_APP"
BUILD_VERSION=$(defaults read "$BUILD_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")
echo "   Version: $BUILD_VERSION"

# Check if AltTab is currently running and quit it
if pgrep -x "${APP_NAME}" > /dev/null; then
    echo "⏹️  Quitting running ${APP_NAME}..."
    osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || killall "${APP_NAME}" 2>/dev/null || true
    sleep 1
    
    # Wait for process to fully quit
    for i in {1..10}; do
        if ! pgrep -x "${APP_NAME}" > /dev/null; then
            break
        fi
        echo "   Waiting for ${APP_NAME} to quit..."
        sleep 0.5
    done
fi

# Backup existing version if it exists
if [ -d "$TARGET_APP" ]; then
    BACKUP="${TARGET_APP}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "💾 Backing up existing ${APP_NAME}.app to:"
    echo "   $BACKUP"
    mv "$TARGET_APP" "$BACKUP"
fi

# Copy new version
echo "📦 Copying ${APP_NAME}.app to /Applications/..."
cp -R "$BUILD_APP" "$TARGET_APP"

# Clear quarantine attribute if present (for locally built apps)
echo "🔓 Clearing quarantine attribute..."
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

# Verify installation
if [ -d "$TARGET_APP" ]; then
    INSTALLED_VERSION=$(defaults read "$TARGET_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")
    echo ""
    echo "✅ Installation successful!"
    echo "   Installed version: $INSTALLED_VERSION"
    echo "   Location: $TARGET_APP"
    echo ""
    
    if [ "$AUTO_LAUNCH" = true ]; then
        echo "🚀 Launching ${APP_NAME}..."
        open "$TARGET_APP"
        echo "✨ ${APP_NAME} launched!"
    else
        echo "🚀 Launch ${APP_NAME}? (Press Enter to launch, Ctrl+C to skip)"
        read
        open "$TARGET_APP"
        echo "✨ ${APP_NAME} launched!"
    fi
else
    echo "❌ Installation failed"
    exit 1
fi
