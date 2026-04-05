#!/usr/bin/env bash
# Vendor AppCenter as: source for Core + Crashes modules + prebuilt PLCrashReporter (macOS slice).
# Drops every other Microsoft module at download time (Analytics/Distribute/Auth/Push/Data).
# Usage: ./vendor/scripts/update_appcenter.sh --update
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

UPSTREAM_VERSION="4.3.0"
GIT_URL="https://github.com/microsoft/appcenter-sdk-apple.git"

# PLCrashReporter ships as a separate prebuilt binary release.
# Bump deliberately if AppCenter source needs a different version at compile time.
PLCRASHREPORTER_VERSION="1.11.1"
PLCRASHREPORTER_URL="https://github.com/microsoft/plcrashreporter/releases/download/${PLCRASHREPORTER_VERSION}/PLCrashReporter-XCFramework-${PLCRASHREPORTER_VERSION}.zip"

DEST="vendor/AppCenter"

require_update_flag "${1:-}" "$0" "refreshes $DEST to AppCenter $UPSTREAM_VERSION + PLCrashReporter $PLCRASHREPORTER_VERSION"
mktempdir

git_clone_tag "$GIT_URL" "$UPSTREAM_VERSION" "$TMP/src"
fetch_extract "$PLCRASHREPORTER_URL" "$TMP/plcr"

rebuild_dest "$DEST" Sources/AppCenter Sources/AppCenterCrashes Frameworks

# Source: only the two modules we use
cp -R "$TMP/src/AppCenter/AppCenter/." "$DEST/Sources/AppCenter/"
cp -R "$TMP/src/AppCenterCrashes/AppCenterCrashes/." "$DEST/Sources/AppCenterCrashes/"

# Drop non-source noise that we don't compile:
#   - Support/ dirs (xcconfigs, modulemaps, plists Microsoft uses for their own build)
#   - Tests
#   - Xcode projects
# Keep include/ — it's the publicHeadersPath SPM consumes for the umbrella module,
# populated with symlinks to the public-API headers.
for d in "$DEST/Sources/AppCenter" "$DEST/Sources/AppCenterCrashes"; do
    rm -rf "$d/Support"
    find "$d" -type d \( -name "Tests" -o -name "Test" -o -name "*.xcodeproj" -o -name "*.xcworkspace" \) \
        -prune -exec rm -rf {} \; 2>/dev/null || true
done

# PLCrashReporter: keep only the macOS slice of the XCFramework.
PLCR_FW="$(find "$TMP/plcr" -maxdepth 3 -name "CrashReporter.xcframework" -type d | head -1)"
[ -n "$PLCR_FW" ] || { echo "ERROR: CrashReporter.xcframework not found in PLCrashReporter zip" >&2; exit 1; }

MACOS_SLICE_DIR="$(find "$PLCR_FW" -maxdepth 1 -type d -name "macos-*" | head -1)"
[ -n "$MACOS_SLICE_DIR" ] || { echo "ERROR: macOS slice not found in CrashReporter.xcframework" >&2; ls -la "$PLCR_FW" >&2; exit 1; }
MACOS_SLICE_NAME="$(basename "$MACOS_SLICE_DIR")"

mkdir -p "$DEST/Frameworks/CrashReporter.xcframework/$MACOS_SLICE_NAME"
cp -R "$MACOS_SLICE_DIR/." "$DEST/Frameworks/CrashReporter.xcframework/$MACOS_SLICE_NAME/"

# Minimal Info.plist advertising only the macOS slice
cat > "$DEST/Frameworks/CrashReporter.xcframework/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>LibraryIdentifier</key>
			<string>$MACOS_SLICE_NAME</string>
			<key>LibraryPath</key>
			<string>CrashReporter.framework</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
				<string>x86_64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>macos</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
EOF

apply_local_patches "$DEST"

# Enumerate every subdirectory containing .h files. SPM has no recursive header-search glob,
# so we emit one .headerSearchPath() per subdir. Regenerated each update so upstream layout
# changes (added/removed subdirs) flow through automatically.
emit_header_paths() {
    local root="$1" prefix="$2"
    (cd "$root" && find . -type d \! -name '.*') | while read -r d; do
        d="${d#./}"
        [ -z "$d" ] && d="."
        # Skip dirs with no .h files
        if compgen -G "$root/$d/*.h" >/dev/null; then
            printf '                .headerSearchPath("%s%s"),\n' "$prefix" "$d"
        fi
    done
}
APPCENTER_HEADER_PATHS="$(emit_header_paths "$DEST/Sources/AppCenter" "")"
CRASHES_OWN_HEADER_PATHS="$(emit_header_paths "$DEST/Sources/AppCenterCrashes" "")"
CRASHES_CROSS_HEADER_PATHS="$(emit_header_paths "$DEST/Sources/AppCenter" "../AppCenter/")"

# Write Package.swift (adapted from microsoft/appcenter-sdk-apple/Package.swift, scoped to
# the Core + Crashes modules we use; PLCrashReporter is a local binaryTarget).
cat > "$DEST/Package.swift" <<EOF
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppCenter",
    platforms: [.macOS(.v10_13)],
    products: [
        // Static (matching Microsoft's own Package.swift). Consumers \`import AppCenter\` /
        // \`import AppCenterCrashes\` and the linker pulls the .o files directly into the
        // host binary. The host target must list these with Embed = "Do Not Embed".
        .library(name: "AppCenter", type: .static, targets: ["AppCenter"]),
        .library(name: "AppCenterCrashes", type: .static, targets: ["AppCenterCrashes"]),
    ],
    targets: [
        .target(
            name: "AppCenter",
            path: "Sources/AppCenter",
            cSettings: [
                .define("APP_CENTER_C_VERSION", to: "\\"${UPSTREAM_VERSION}\\""),
                .define("APP_CENTER_C_BUILD", to: "\\"1\\""),
$APPCENTER_HEADER_PATHS
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("sqlite3"),
                .linkedFramework("Foundation"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreTelephony"),
            ]
        ),
        .target(
            name: "AppCenterCrashes",
            dependencies: ["AppCenter", "PLCrashReporter"],
            path: "Sources/AppCenterCrashes",
            cSettings: [
$CRASHES_OWN_HEADER_PATHS
$CRASHES_CROSS_HEADER_PATHS
                // PLCrashReporter public headers — AppCenterCrashes uses \`#import "CrashReporter.h"\` (quoted).
                .headerSearchPath("../../Frameworks/CrashReporter.xcframework/${MACOS_SLICE_NAME}/CrashReporter.framework/Headers"),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
            ]
        ),
        .binaryTarget(
            name: "PLCrashReporter",
            path: "Frameworks/CrashReporter.xcframework"
        ),
    ]
)
EOF

write_upstream "$DEST" "appcenter-${UPSTREAM_VERSION} + PLCrashReporter-${PLCRASHREPORTER_VERSION}" "$GIT_URL"
done_msg "$DEST" "AppCenter $UPSTREAM_VERSION + PLCrashReporter $PLCRASHREPORTER_VERSION"
