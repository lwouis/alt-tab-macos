#!/usr/bin/env bash
# Debug helper for the cancelShortcut (Escape) key event bug.
# Stops competing window switchers (which steal keyboard events), applies debug
# settings, launches the AltTab debug build, and restores settings on exit.

set -euo pipefail

BUNDLE_ID="com.lwouis.alt-tab-macos"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Locate debug build: repo-local DerivedData, then Xcode default
DERIVED_DATA="${DERIVED_DATA:-$REPO_ROOT/DerivedData}"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/AltTabDebug.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
    XCODE_BUILD=$(find ~/Library/Developer/Xcode/DerivedData \
        -name "AltTabDebug.app" -path "*/Debug/AltTabDebug.app" -type d 2>/dev/null | head -1)
    APP_BUNDLE="${XCODE_BUILD:-$APP_BUNDLE}"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "ERROR: Debug build not found. Run: bash ai/build.sh first"
    exit 1
fi

# Save original shortcutStyle and restore on exit
ORIG_STYLE=$(defaults read "$BUNDLE_ID" shortcutStyle 2>/dev/null || echo "0")
restore() {
    echo ""
    echo "Restoring shortcutStyle → $ORIG_STYLE"
    defaults write "$BUNDLE_ID" shortcutStyle -int "$ORIG_STYLE"
}
trap restore EXIT

# Stop competing window switchers — they install CGEventTaps that swallow Escape
# before AltTab's local NSEvent monitor ever sees it
SWITCHERS=(Contexts Witch Overflow HiDock)
echo "=== Competing window switchers ==="
for app in "${SWITCHERS[@]}"; do
    pid=$(pgrep -ix "$app" 2>/dev/null || true)
    if [[ -n "$pid" ]]; then
        echo "  $app: RUNNING — matching processes:"
        pgrep -il "$app" | sed 's/^/    /'
        pkill -ix "$app" && echo "  $app: stopped." || echo "  $app: stop failed (continuing anyway)"
        sleep 0.3
    else
        echo "  $app: not running"
    fi
done
echo ""

# Kill any running AltTab so fresh settings take effect
killall AltTab 2>/dev/null || true
sleep 0.3

# shortcutStyle=2 (searchOnRelease): overlay stays open after ⌥ is released,
# forcing the user to press Escape to close — the most reliable path to reproduce
# the cancelShortcut key-window bug.
# 0=focusOnRelease  1=doNothingOnRelease  2=searchOnRelease
defaults write "$BUNDLE_ID" shortcutStyle -int 2

echo "Debug settings applied:"
echo "  shortcutStyle → 2 (searchOnRelease)"
echo ""
echo "Reproduce the Escape bug:"
echo "  1. Press your hold shortcut + Tab  — overlay opens"
echo "  2. Release hold key               — overlay stays open (searchOnRelease)"
echo "  3. Press Escape                   — should close overlay"
echo ""
echo "Launching: $APP_BUNDLE"
echo "---"
open -a "$APP_BUNDLE" --args --logs=debug
