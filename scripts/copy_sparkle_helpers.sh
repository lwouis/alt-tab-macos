#!/usr/bin/env bash
# Build phase script for the alt-tab-macos target. Wired from the "Copy Sparkle Helpers"
# build phase via $(SRCROOT)/scripts/copy_sparkle_helpers.sh.
#
# Runs after Xcode's Embed Frameworks phase, before Xcode's final code-signing of AltTab.app:
#   1. Copy Sparkle's prebuilt Updater.app + Autoupdate (already Developer ID-signed at
#      vendor time by vendor/scripts/update_sparkle.sh) into Sparkle.framework/Versions/A/,
#      AND add the top-level Sparkle.framework/Autoupdate and /Updater.app symlinks. Sparkle's
#      installer locates these via `-[NSBundle URLForAuxiliaryExecutable:]` which only walks the
#      framework root — so the symlinks (or the files themselves at framework root, like
#      upstream's release tarball ships them) are mandatory. Putting them under Resources/
#      makes the API return nil and Sparkle 2 fails the self-update with "Cannot retrieve path
#      for auxiliary tool: Autoupdate" → "An error occurred while launching the installer".
#   2. Mirror the SPM-generated Sparkle_Sparkle.bundle content (lprojs + nibs + css) into
#      Versions/A/Resources/, plus into PackageFrameworks/Sparkle.framework for Debug-build
#      bundleForClass: resolution.
#   3. Rewrite Sparkle.framework's CFBundleIdentifier from SPM's auto-generated 'sparkle.Sparkle'
#      to the upstream-canonical 'org.sparkle-project.Sparkle' so Sparkle's localization +
#      helper lookups (which hardcode that identifier) work.
#
# Re-seals Sparkle.framework at the end — see comment near codesign call.
set -euo pipefail

SPARKLE_FW="$BUILT_PRODUCTS_DIR/$FRAMEWORKS_FOLDER_PATH/Sparkle.framework"
SPARKLE_VERSIONED="$SPARKLE_FW/Versions/A"
APP_RES="$BUILT_PRODUCTS_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
SPM_BUNDLE="$BUILT_PRODUCTS_DIR/Sparkle_Sparkle.bundle"
# Debug builds load Sparkle.framework via Xcode's absolute PackageFrameworks rpath
# (baked into the linker invocation, not driven by xcconfig). bundleForClass: therefore
# returns the PackageFrameworks copy, not the embedded one — so resources must live there too.
SPARKLE_PKG="$BUILT_PRODUCTS_DIR/PackageFrameworks/Sparkle.framework/Versions/A"

# IntelliJ/AppCode sometimes runs this phase before Embed Frameworks has finished
# materialising Versions/A/. Wait up to 10s for the physical framework dir to exist
# before proceeding. (Xcode serialises phases so this loop is a single-iteration no-op there.)
for _ in $(seq 1 100); do
    [ -d "$SPARKLE_VERSIONED" ] && break
    sleep 0.1
done
if [ ! -d "$SPARKLE_VERSIONED" ]; then
    echo "error: $SPARKLE_VERSIONED not found — Embed Frameworks must run before this phase" >&2
    exit 1
fi

# Write through the physical path (Versions/A/Resources). The top-level Resources symlink
# resolves here at runtime; touching the symlink first would race the Embed phase.
mkdir -p "$SPARKLE_VERSIONED/Resources"

# Prebuilt helpers — go at Versions/A/ next to the Sparkle binary (NOT inside Resources/), to
# match upstream Sparkle 2's framework layout. Replace any existing copies from prior builds —
# including legacy copies that earlier builds wrote to Resources/.
rm -rf "$SPARKLE_VERSIONED/Resources/Updater.app" "$SPARKLE_VERSIONED/Resources/Autoupdate" \
       "$SPARKLE_VERSIONED/Updater.app"           "$SPARKLE_VERSIONED/Autoupdate"
cp -R "$SRCROOT/vendor/Sparkle/Helpers/Updater.app" "$SPARKLE_VERSIONED/"
cp    "$SRCROOT/vendor/Sparkle/Helpers/Autoupdate"  "$SPARKLE_VERSIONED/"

# Top-level framework symlinks. -[NSBundle URLForAuxiliaryExecutable:] walks only the framework
# root, so without these symlinks (or the files themselves at the root) Sparkle 2's installer
# cannot find Autoupdate/Updater.app and fails the self-update at submit-installer time.
# We use Versions/Current/<name> targets to mirror upstream's release-tarball layout exactly.
(
    cd "$SPARKLE_FW"
    ln -sfn Versions/Current/Autoupdate  Autoupdate
    ln -sfn Versions/Current/Updater.app Updater.app
)

# Mirror SPM-generated resource bundle (lprojs + nibs + css) into the framework.
# Read from the SPM output ($BUILT_PRODUCTS_DIR/Sparkle_Sparkle.bundle), which exists before
# Xcode copies it to $APP_RES — avoids ordering races on incremental builds.
# rsync (not mv) tolerates pre-existing dirs from prior builds.
if [ -d "$SPM_BUNDLE/Contents/Resources" ]; then
    rsync -a "$SPM_BUNDLE/Contents/Resources/" "$SPARKLE_VERSIONED/Resources/"
fi

# Xcode also copies Sparkle_Sparkle.bundle into $APP_RES (we can't disable that auto-embed).
# Remove that redundant copy so the framework is the single source of truth at runtime.
rm -rf "$APP_RES/Sparkle_Sparkle.bundle"

# Mirror resources into the PackageFrameworks copy so Debug builds (which load Sparkle.framework
# from that absolute path) can find them via bundleForClass:. Helpers are not needed there since
# the helper invocation path is rooted at the embedded framework via the host process.
if [ -d "$SPARKLE_PKG" ]; then
    mkdir -p "$SPARKLE_PKG/Resources"
    if [ -d "$SPM_BUNDLE/Contents/Resources" ]; then
        rsync -a "$SPM_BUNDLE/Contents/Resources/" "$SPARKLE_PKG/Resources/"
    fi
fi

# Rewrite CFBundleIdentifier to the upstream-canonical value. SPM auto-generates 'sparkle.Sparkle'
# from the package+target name, but Sparkle's localization lookup uses [NSBundle bundleWithIdentifier:
# @"org.sparkle-project.Sparkle"] (matching the SPARKLE_BUNDLE_IDENTIFIER compile define), and the
# prebuilt Autoupdate/Updater helpers hardcode the same identifier. Without this patch, Sparkle's
# localized strings fall through to the main bundle (which has no Sparkle.strings) and render in
# English regardless of AppleLanguages.
for plist in "$SPARKLE_VERSIONED/Resources/Info.plist" "$SPARKLE_PKG/Resources/Info.plist"; do
    [ -f "$plist" ] && plutil -replace CFBundleIdentifier -string "org.sparkle-project.Sparkle" "$plist"
done

# Re-seal Sparkle.framework so its _CodeSignature/CodeResources reflects our CFBundleIdentifier
# rewrite + the helper/resource copies above. We don't have to sign Updater.app / Autoupdate —
# those are pre-signed with the maintainer's Developer ID at vendor time (see
# vendor/scripts/update_sparkle.sh) and their seals deeper than --deep walks, so Xcode's final
# pass on AltTab.app never touches them.
# Why this can't be Xcode's --deep alone: Release adds --deep via release.xcconfig and Xcode does
# re-seal Sparkle.framework, but Debug uses --timestamp=none without --deep, leaving the SPM
# linker-signed adhoc seal in place — which then fails `codesign --verify --deep --strict`
# because that seal references resources the framework no longer matches.
IDENT="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
codesign --force --sign "$IDENT" "$SPARKLE_FW"
