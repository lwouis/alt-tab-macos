#!/usr/bin/env bash
# One-time dev environment setup for building AltTab locally.
# Run this once after cloning, or after installing Xcode fresh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Step 1: Verify Xcode ==="
if ! xcode-select -p | grep -q Xcode; then
    echo "ERROR: Xcode not selected. Install Xcode from the App Store, then run:"
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi
echo "  Xcode: $(xcode-select -p)"

echo ""
echo "=== Step 2: Accept Xcode license ==="
sudo xcodebuild -license accept 2>/dev/null && echo "  License accepted." || echo "  Already accepted."

echo ""
echo "=== Step 3: Run first launch ==="
sudo xcodebuild -runFirstLaunch 2>&1 | tail -2

echo ""
echo "=== Step 4: Create local codesign certificate ==="
if security find-certificate -c "Local Self-Signed" ~/Library/Keychains/login.keychain-db &>/dev/null; then
    echo "  Certificate already exists."
else
    cd "$REPO_ROOT"
    bash scripts/codesign/setup_local.sh
    echo "  Certificate created and trusted."
fi

echo ""
echo "=== Step 5: Install CocoaPods dependencies ==="
cd "$REPO_ROOT"
if [ ! -d Pods ]; then
    pod install
else
    echo "  Pods already installed."
fi

echo ""
echo "=== Done. Run: bash ai/build.sh ==="
echo ""
echo "NOTE: First build will prompt for keychain password multiple times."
echo "      Enter your login keychain password and click 'Always Allow' each time."
echo "      Subsequent builds will not prompt."
