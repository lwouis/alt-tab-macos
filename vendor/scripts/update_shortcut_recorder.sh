#!/usr/bin/env bash
# Vendor ShortcutRecorder as pure source. No helpers, no prebuilt binaries.
# Usage: ./vendor/scripts/update_shortcut_recorder.sh --update
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

UPSTREAM_COMMIT="52c6273d233f7794e4fd5d22f50d2de0e4e41b19"
UPSTREAM_BRANCH="alt-tab-current"
GIT_URL="https://github.com/lwouis/ShortcutRecorder.git"
DEST="vendor/ShortcutRecorder"

require_update_flag "${1:-}" "$0" "refreshes $DEST to ${UPSTREAM_COMMIT:0:8}"
mktempdir

UPSTREAM_SHA="$(git_clone_commit "$GIT_URL" "$UPSTREAM_COMMIT" "$TMP/src")"

rebuild_dest "$DEST" Sources/ShortcutRecorder/include/ShortcutRecorder

# .m files at the target root (alongside resources). Headers go into include/ShortcutRecorder/
# so SPM's publicHeadersPath = "include" resolves `#import <ShortcutRecorder/Foo.h>` correctly
# (which is how upstream's source uses them).
cp "$TMP/src/Library/"*.m "$DEST/Sources/ShortcutRecorder/"
cp "$TMP/src/Library/"*.h "$DEST/Sources/ShortcutRecorder/include/ShortcutRecorder/"

# Resources at the target root. SPM auto-detects .xcassets and .lproj when defaultLocalization is set.
if [ -d "$TMP/src/Resources" ]; then
    cp -R "$TMP/src/Resources/Images.xcassets" "$DEST/Sources/ShortcutRecorder/" 2>/dev/null || true
    copy_kept_lprojs "$TMP/src/Resources" "$DEST/Sources/ShortcutRecorder"
fi

# Patch SRBundle() to find the SPM-generated resource bundle. The vendored source uses
# `bundleWithIdentifier:@"com.kulakov.ShortcutRecorder"` which only works when distributed
# as a framework (CocoaPods). With SPM static linking the bundle has a different identifier;
# look it up by name from the main bundle's resources path.
patch_sr_bundle() {
    local f="$DEST/Sources/ShortcutRecorder/SRCommon.m"
    [ -f "$f" ] || return 0
    sed -i.bak '/Bundle = \[NSBundle bundleWithIdentifier:@"com.kulakov.ShortcutRecorder"\];/c\
        NSURL *bundleURL = [[NSBundle mainBundle] URLForResource:@"ShortcutRecorder_ShortcutRecorder" withExtension:@"bundle"];\
        Bundle = bundleURL ? [NSBundle bundleWithURL:bundleURL] : [NSBundle bundleWithIdentifier:@"com.kulakov.ShortcutRecorder"];
' "$f"
    rm -f "$f.bak"
}
patch_sr_bundle

apply_local_patches "$DEST"

# Write Package.swift (regenerated each update so the manifest stays in sync with the layout)
cat > "$DEST/Package.swift" <<'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShortcutRecorder",
    defaultLocalization: "en",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ShortcutRecorder", type: .static, targets: ["ShortcutRecorder"]),
    ],
    targets: [
        .target(
            name: "ShortcutRecorder",
            path: "Sources/ShortcutRecorder",
            resources: [.process("Images.xcassets")],
            publicHeadersPath: "include",
            cSettings: [
                // Lets .m files use `#import "SRCommon.h"` as well as `<ShortcutRecorder/SRCommon.h>`.
                .headerSearchPath("include/ShortcutRecorder"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
EOF

write_upstream "$DEST" "$UPSTREAM_BRANCH@$UPSTREAM_SHA" "$GIT_URL"
done_msg "$DEST" "${UPSTREAM_SHA:0:8}"
