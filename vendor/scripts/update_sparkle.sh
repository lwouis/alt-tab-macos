#!/usr/bin/env bash
# Vendor Sparkle as: source library (we compile, DCE-friendly) + prebuilt helpers (upstream-signed).
# Usage: ./vendor/scripts/update_sparkle.sh --update
#
# The Sparkle library target in upstream's xcodeproj compiles 67 .m files across 6 directories
# (Sparkle, Autoupdate, Downloader, InstallerConnection, InstallerLauncher, InstallerStatus) plus
# the ed25519 C library. The 23 public headers (and what consumers should import) live in
# Sparkle.framework/Versions/B/Headers/ in the prebuilt release. We mirror all of this into a
# single SPM target under vendor/Sparkle/Sources/Sparkle/.
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

UPSTREAM_VERSION="2.9.1"
RELEASE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${UPSTREAM_VERSION}/Sparkle-${UPSTREAM_VERSION}.tar.xz"
GIT_URL="https://github.com/sparkle-project/Sparkle.git"
DEST="vendor/Sparkle"

# Exact .m files the upstream "Sparkle" framework target compiles. Extracted from
# Sparkle.xcodeproj's PBXSourcesBuildPhase for that target. 67 files, sorted.
SPARKLE_LIB_SOURCES=(
    Autoupdate/SPUInstallationInfo.m
    Autoupdate/SPUInstallationInputData.m
    Autoupdate/SPUMessageTypes.m
    Autoupdate/SUCodeSigningVerifier.m
    Autoupdate/SUSignatureVerifier.m
    Downloader/SPUDownloader.m
    InstallerConnection/SUInstallerConnection.m
    InstallerConnection/SUXPCInstallerConnection.m
    InstallerLauncher/SUInstallerLauncher.m
    InstallerStatus/SUInstallerStatus.m
    InstallerStatus/SUXPCInstallerStatus.m
    Sparkle/SPUAppcastItemState.m
    Sparkle/SPUAppcastItemStateResolver.m
    Sparkle/SPUAutomaticUpdateDriver.m
    Sparkle/SPUBasicUpdateDriver.m
    Sparkle/SPUCoreBasedUpdateDriver.m
    Sparkle/SPUDownloadData.m
    Sparkle/SPUDownloadDriver.m
    Sparkle/SPUDownloadedUpdate.m
    Sparkle/SPUExtractSignedFeed.m
    Sparkle/SPUInformationalUpdate.m
    Sparkle/SPUInstallerDriver.m
    Sparkle/SPULocalCacheDirectory.m
    Sparkle/SPUNoUpdateFoundInfo.m
    Sparkle/SPUProbeInstallStatus.m
    Sparkle/SPUProbingUpdateDriver.m
    Sparkle/SPUScheduledUpdateDriver.m
    Sparkle/SPUSecureCoding.m
    Sparkle/SPUSkippedUpdate.m
    Sparkle/SPUStandardUpdaterController.m
    Sparkle/SPUStandardUserDriver.m
    Sparkle/SPUStandardVersionDisplay.m
    Sparkle/SPUUIBasedUpdateDriver.m
    Sparkle/SPUUpdatePermissionRequest.m
    Sparkle/SPUUpdater.m
    Sparkle/SPUUpdaterCycle.m
    Sparkle/SPUUpdaterSettings.m
    Sparkle/SPUUpdaterTimer.m
    Sparkle/SPUUserAgent+Private.m
    Sparkle/SPUUserInitiatedUpdateDriver.m
    Sparkle/SPUUserUpdateState.m
    Sparkle/SPUVerifierInformation.m
    Sparkle/SPUXPCServiceInfo.m
    Sparkle/SUAppcast.m
    Sparkle/SUAppcastDriver.m
    Sparkle/SUAppcastItem.m
    Sparkle/SUApplicationInfo.m
    Sparkle/SUConstants.m
    Sparkle/SUFileManager.m
    Sparkle/SUHost.m
    Sparkle/SULegacyWebView.m
    Sparkle/SULog+NSError.m
    Sparkle/SULog.m
    Sparkle/SUOperatingSystem.m
    Sparkle/SUPhasedUpdateGroupInfo.m
    Sparkle/SUReleaseNotesCommon.m
    Sparkle/SUSignatures.m
    Sparkle/SUStandardVersionComparator.m
    Sparkle/SUStatusController.m
    Sparkle/SUSystemProfiler.m
    Sparkle/SUTextViewReleaseNotesView.m
    Sparkle/SUTouchBarButtonGroup.m
    Sparkle/SUUpdateAlert.m
    Sparkle/SUUpdatePermissionPrompt.m
    Sparkle/SUUpdatePermissionResponse.m
    Sparkle/SUUpdater.m
    Sparkle/SUWKWebView.m
)

require_update_flag "${1:-}" "$0" "refreshes $DEST to Sparkle $UPSTREAM_VERSION (source library + prebuilt helpers)"
mktempdir

git_clone_tag "$GIT_URL" "$UPSTREAM_VERSION" "$TMP/src"
fetch_extract "$RELEASE_URL" "$TMP"
PREBUILT_FW="$TMP/Sparkle.framework"

rebuild_dest "$DEST" Sources/Sparkle/include/Sparkle Sources/Sparkle/internal Sources/Sparkle/ed25519 Helpers bin

# Headers split:
#   - The 23 public-API headers (from the prebuilt framework's Headers/) go in include/Sparkle/.
#     These define the module's umbrella surface — what Sparkle.h imports.
#   - Every other .h (internal) goes in internal/ alongside the .m files.
#     Internal headers stay reachable via `#import "Foo.h"` (cSettings.headerSearchPath("internal"))
#     but aren't visible to the module verifier.
# Headers that need to live in include/Sparkle/ so internal code can reach them via
# <Sparkle/X.h> imports. Two groups:
#   - Public API (23 headers from Sparkle.framework/Versions/B/Headers/) — what consumers import.
#   - Cross-target internal headers (7 headers from PrivateHeaders/) — internal code references
#     them via <Sparkle/X.h> because in upstream's framework build they live alongside public
#     ones inside Sparkle.framework/Versions/B/PrivateHeaders/.
SPARKLE_PUBLIC_HEADERS=(
    SPUAppcastSigningValidationStatus.h SPUDownloadData.h SPUStandardUpdaterController.h
    SPUStandardUserDriver.h SPUStandardUserDriverDelegate.h SPUUpdateCheck.h
    SPUUpdatePermissionRequest.h SPUUpdater.h SPUUpdaterDelegate.h SPUUpdaterSettings.h
    SPUUserDriver.h SPUUserUpdateState.h SUAppcast.h SUAppcastItem.h SUErrors.h SUExport.h
    SUStandardVersionComparator.h SUUpdatePermissionResponse.h SUUpdater.h SUUpdaterDelegate.h
    SUVersionComparisonProtocol.h SUVersionDisplayProtocol.h Sparkle.h
    SPUAppcastItemStateResolver.h SPUGentleUserDriverReminders.h SPUInstallationType.h
    SPUStandardUserDriver+Private.h SPUUserAgent+Private.h SUAppcastItem+Private.h
    SUInstallerLauncher+Private.h
)

# Build a lookup of public-header basenames.
declare -A IS_PUBLIC=()
for h in "${SPARKLE_PUBLIC_HEADERS[@]}"; do IS_PUBLIC[$h]=1; done

# Walk every .h in the 6 library directories. Route public headers to include/Sparkle/,
# everything else to internal/.
for dir in Sparkle Autoupdate Downloader InstallerConnection InstallerLauncher InstallerStatus; do
    for src in "$TMP/src/$dir"/*.h; do
        [ -e "$src" ] || continue
        base="$(basename "$src")"
        if [ -n "${IS_PUBLIC[$base]:-}" ]; then
            cp "$src" "$DEST/Sources/Sparkle/include/Sparkle/"
        else
            cp "$src" "$DEST/Sources/Sparkle/internal/"
        fi
    done
done

# 2. Copy only the .m files that compile into the library target (the 67 listed above).
for src in "${SPARKLE_LIB_SOURCES[@]}"; do
    cp "$TMP/src/$src" "$DEST/Sources/Sparkle/"
done

# 3. Copy the 3 xibs (compiled to .nib at SPM build time).
cp "$TMP/src/Sparkle/SUStatus.xib"                   "$DEST/Sources/Sparkle/"
cp "$TMP/src/Sparkle/SUUpdateAlert.xib"              "$DEST/Sources/Sparkle/"
cp "$TMP/src/Sparkle/SUUpdatePermissionPrompt.xib"   "$DEST/Sources/Sparkle/"

# 4. Copy lprojs we ship + Base.lproj.
cp -R "$TMP/src/Sparkle/Base.lproj" "$DEST/Sources/Sparkle/"
copy_kept_lprojs "$TMP/src/Sparkle" "$DEST/Sources/Sparkle"

# 5. Copy release-notes CSS from top-level Resources/.
cp "$TMP/src/Resources/ReleaseNotesColorStyle.css" "$DEST/Sources/Sparkle/"

# 6. Vendor ed25519 C source into a sub-target directory (compiled into the same library).
cp "$TMP/src/Vendor/ed25519-sparkle/src/"*.{c,h} "$DEST/Sources/Sparkle/ed25519/"

# 7. Custom modulemap at include/ defines the umbrella module. Directory umbrella ("Sparkle")
#    means EVERY .h in include/Sparkle/ becomes a module member — this includes the 7 internal
#    cross-target headers we copied above. Without a directory umbrella, Clang's strict mode
#    rejects each header that the explicit umbrella header (Sparkle.h) doesn't #import.
cat > "$DEST/Sources/Sparkle/include/module.modulemap" <<'EOF'
module Sparkle {
    umbrella "Sparkle"
    export *
    module * { export * }
}
EOF

# 9. Prebuilt helpers from the release tarball. Upstream ships them adhoc-signed
# (Signature=adhoc, TeamIdentifier=not set) — notarytool rejects nested adhoc-signed Mach-O.
# Re-sign here with the maintainer's Developer ID so the helpers can be committed pre-signed
# and the per-build "Copy Sparkle Helpers" phase doesn't need a codesign step. The host app's
# final --deep pass only recurses into Contents/Frameworks/ (one level), it never descends
# into a framework's Resources/, so we must do this signing somewhere — once at vendor time
# beats once per clean build.
cp -R "$PREBUILT_FW/Versions/B/Updater.app" "$DEST/Helpers/"
cp    "$PREBUILT_FW/Versions/B/Autoupdate"  "$DEST/Helpers/"
SPARKLE_HELPER_IDENT="${SPARKLE_HELPER_IDENT:-$(security find-identity -v -p codesigning | awk -F\" '/Developer ID Application/ {print $2; exit}')}"
if [ -z "$SPARKLE_HELPER_IDENT" ]; then
    echo "error: no 'Developer ID Application' identity in keychain — set SPARKLE_HELPER_IDENT or import the cert before running this script" >&2
    echo "  (the maintainer must run update_sparkle.sh with the release-signing cert; the committed signed helpers are what the CI release uses)" >&2
    exit 1
fi
codesign --force --sign "$SPARKLE_HELPER_IDENT" --options runtime --timestamp "$DEST/Helpers/Updater.app"
codesign --force --sign "$SPARKLE_HELPER_IDENT" --options runtime --timestamp "$DEST/Helpers/Autoupdate"

# 10. Only the sign_update CLI tool (drop generate_appcast, generate_keys, BinaryDelta).
cp "$TMP/bin/sign_update" "$DEST/bin/"
chmod +x "$DEST/bin/sign_update" "$DEST/Helpers/Autoupdate"

apply_local_patches "$DEST"

# Write Package.swift (regenerated each update so the manifest stays in sync with the layout).
cat > "$DEST/Package.swift" <<'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sparkle",
    defaultLocalization: "en",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "Sparkle", type: .dynamic, targets: ["Sparkle"]),
    ],
    targets: [
        .target(
            name: "Sparkle",
            path: "Sources/Sparkle",
            resources: [
                .process("SUStatus.xib"),
                .process("SUUpdateAlert.xib"),
                .process("SUUpdatePermissionPrompt.xib"),
                .process("ReleaseNotesColorStyle.css"),
            ],
            publicHeadersPath: "include",
            cSettings: [
                // internal/ holds the ~100 private headers (public ones are in include/Sparkle/
                // via publicHeadersPath). Lets .m files use `#import "Foo.h"` for private headers.
                .headerSearchPath("internal"),
                // include/Sparkle/ for `#import "Foo.h"` style references to public headers.
                .headerSearchPath("include/Sparkle"),
                // include/ (parent of Sparkle/) for `#import <Sparkle/Foo.h>` style references —
                // used by private headers that depend on the public API.
                .headerSearchPath("include"),
                // Lets SUSignatureVerifier.m use `#import "ed25519.h"`.
                .headerSearchPath("ed25519"),

                // Defines from upstream's ConfigCommon.xcconfig + ConfigFramework.xcconfig.
                // Macros mapping objc_direct attributes — required for headers using SPU_OBJC_DIRECT.
                .define("SPU_OBJC_DIRECT", to: "__attribute__((objc_direct))"),
                .define("SPU_OBJC_DIRECT_MEMBERS", to: "__attribute__((objc_direct_members))"),
                // Identifies us as the Sparkle library build (not a Sparkle helper or consumer).
                .define("BUILDING_SPARKLE", to: "1"),
                // Feature toggles. Setting legacy code paths to 0 lets the linker strip them.
                .define("SPARKLE_BUILD_UI_BITS", to: "1"),
                .define("SPARKLE_COPY_LOCALIZATIONS", to: "1"),
                .define("SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME", to: "0"),
                .define("SPARKLE_BUILD_LEGACY_SUUPDATER", to: "0"),
                .define("SPARKLE_BUILD_LEGACY_DSA_SUPPORT", to: "0"),
                .define("SPARKLE_BUILD_PACKAGE_SUPPORT", to: "0"),
                .define("SPARKLE_BUILD_LEGACY_DELTA_SUPPORT", to: "0"),
                .define("SPARKLE_BUILD_BZIP2_DELTA_SUPPORT", to: "0"),
                .define("GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT", to: "0"),
                // String constants the library references at runtime. We don't embed XPC services.
                .define("SPARKLE_BUNDLE_IDENTIFIER", to: "\"org.sparkle-project.Sparkle\""),
                .define("CURRENT_PROJECT_VERSION", to: "\"2054\""),
                .define("MARKETING_VERSION", to: "\"2.9.1\""),
                .define("SPARKLE_RELAUNCH_TOOL_NAME", to: "\"Autoupdate\""),
                .define("SPARKLE_INSTALLER_PROGRESS_TOOL_NAME", to: "\"Updater\""),
                .define("SPARKLE_INSTALLER_PROGRESS_TOOL_BUNDLE_ID", to: "\"org.sparkle-project.Sparkle.Updater\""),
                .define("SPARKLE_ICON_NAME", to: "\"AppIcon\""),
                .define("INSTALLER_LAUNCHER_NAME", to: "\"Installer\""),
                .define("INSTALLER_LAUNCHER_BUNDLE_ID", to: "\"org.sparkle-project.InstallerLauncher\""),
                .define("INSTALLER_LAUNCHER_XPC_SERVICE_EMBEDDED", to: "0"),
                .define("INSTALLER_CONNECTION_NAME", to: "\"InstallerConnection\""),
                .define("INSTALLER_CONNECTION_BUNDLE_ID", to: "\"org.sparkle-project.InstallerConnection\""),
                .define("INSTALLER_CONNECTION_XPC_SERVICE_EMBEDDED", to: "0"),
                .define("INSTALLER_STATUS_NAME", to: "\"InstallerStatus\""),
                .define("INSTALLER_STATUS_BUNDLE_ID", to: "\"org.sparkle-project.InstallerStatus\""),
                .define("INSTALLER_STATUS_XPC_SERVICE_EMBEDDED", to: "0"),
                .define("DOWNLOADER_NAME", to: "\"Downloader\""),
                .define("DOWNLOADER_BUNDLE_ID", to: "\"org.sparkle-project.DownloaderService\""),
                .define("DOWNLOADER_XPC_SERVICE_EMBEDDED", to: "0"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
    ]
)
EOF

write_upstream "$DEST" "$UPSTREAM_VERSION" "$RELEASE_URL"
done_msg "$DEST" "$UPSTREAM_VERSION"
