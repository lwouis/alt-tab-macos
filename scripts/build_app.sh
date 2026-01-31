#!/usr/bin/env bash

set -e

# Build script for AltTab - Enhanced for rapid development iteration
#
# This script was enhanced to support AI-assisted development workflows:
# - Builds Debug by default (faster compilation, includes performance logging)
# - Optionally installs to /Applications for immediate testing
# - Optionally launches the app to verify changes instantly
# - Saves full build logs to logs/ directory (timestamped, git-ignored)
# - Shows last 20 lines of output (full log available in logs/)
# - Supports developer code signing via environment variables (not committed)
#
# This enables rapid iteration cycles:
#   ./scripts/build_app.sh Debug --install --launch
#   → Build → Install → Launch → Test → Repeat
#
# Usage: ./scripts/build_app.sh [Debug|Release] [--install|-i] [--launch|-l]
# Default: Debug (most dev work happens here, includes DEBUG-only perf logging)
# Options:
#   --install, -i: Install to /Applications after build
#   --launch, -l: Launch after install (implies --install)
#
# Code Signing (optional, via environment variables):
#   DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/build_app.sh Debug
#   - Or add to ~/.zshrc: export DEVELOPMENT_TEAM="XXXXXXXXXX"
#   - Find your team ID at: https://developer.apple.com/account
#   - Benefits: Persistent permissions, proper code signing
#   - If not set: Uses adhoc signing (fine for local dev)

BUILD_CONFIG="${1:-Debug}"
DO_INSTALL=false
DO_LAUNCH=false

# Parse flags
for arg in "$@"; do
    case "$arg" in
        --install|-i)
            DO_INSTALL=true
            ;;
        --launch|-l)
            DO_INSTALL=true
            DO_LAUNCH=true
            ;;
        Debug|Release)
            # Already handled
            ;;
    esac
done

echo "🔨 Building ${BUILD_CONFIG} configuration..."

# Determine scheme based on config
SCHEME="${BUILD_CONFIG}"

# Build xcodebuild arguments
XCODE_ARGS=(
    -workspace alt-tab-macos.xcworkspace
    -scheme "${SCHEME}"
    -configuration "${BUILD_CONFIG}"
)

# Add code signing if DEVELOPMENT_TEAM is set (keeps credentials out of git)
if [ -n "${DEVELOPMENT_TEAM}" ]; then
    echo "🔐 Using developer team: ${DEVELOPMENT_TEAM}"
    XCODE_ARGS+=(
        DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}"
        CODE_SIGN_STYLE=Automatic
        CODE_SIGN_IDENTITY="Apple Development"
    )
else
    echo "ℹ️  No DEVELOPMENT_TEAM set, using adhoc signing"
    echo "   (Set DEVELOPMENT_TEAM env var for proper code signing)"
fi

# Create logs directory and generate log filename
LOG_DIR="logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/build_$(date +%Y%m%d_%H%M%S).log"

# Build the project and save full log
echo "📝 Saving full build log to: ${LOG_FILE}"
set -o pipefail && xcodebuild "${XCODE_ARGS[@]}" build 2>&1 | tee "${LOG_FILE}" | tail -20

echo ""
echo "✅ Build succeeded!"
echo "📄 Full log: ${LOG_FILE}"

# Install if requested
if [ "$DO_INSTALL" = true ]; then
    echo ""
    if [ "$DO_LAUNCH" = true ]; then
        ./scripts/install_local_build.sh "${BUILD_CONFIG}" --launch
    else
        ./scripts/install_local_build.sh "${BUILD_CONFIG}"
    fi
fi
