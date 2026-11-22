#!/bin/bash
# Personal build: sync with Upstream, test, build, verify the signature, install over /Applications/AltTab.app.
set -euo pipefail
cd "$(dirname "$0")"

app=DerivedData/Build/Products/Release/AltTab.app
fail() { echo "FAIL: $*" >&2; exit 1; }
# At most one AltTab may run, and only from /Applications: a copy from another path is a second app to
# LaunchServices, so both run and draw two switchers. Sets $running to its pid, or empty.
check_running() {
  running=$(pgrep -x AltTab || true)
  if [[ $(wc -w <<<"$running") -gt 1 ]]; then
    for p in $running; do ps -o pid=,comm= -p "$p"; done
    fail "more than one AltTab is running; quit them all with: pkill -x AltTab"
  fi
  if [[ -n $running && $(ps -o comm= -p "$running") != /Applications/AltTab.app/Contents/MacOS/AltTab ]]; then
    fail "AltTab is running from $(ps -o comm= -p "$running"), not /Applications; quit it with: pkill -x AltTab"
  fi
}

# a. Preflight
[[ $(uname) == Darwin ]] || fail "not macOS"
# Capture before grepping: `cmd | grep -q` SIGPIPEs cmd on the first match, and pipefail turns that into a failure.
xcode=$(xcodebuild -version)
xcode_major=$(sed -n 's/^Xcode \([0-9]*\).*/\1/p' <<<"$xcode")
[[ ${xcode_major:-0} -ge 26 ]] || fail "Xcode 26 or later required"
ids=$(security find-identity -v -p codesigning)
grep -q '"Local Self-Signed"' <<<"$ids" || fail "Local Self-Signed signing identity missing"
python3 --version >/dev/null || fail "python3 missing"
[[ $(git remote get-url origin) == *nathanwcyang/alt-tab-nathan* ]] || fail "origin is not the fork"
[[ -z $(git status --porcelain) ]] || fail "working tree not clean"
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream https://github.com/lwouis/alt-tab-macos.git
[[ $(git branch --show-current) == personal ]] || fail "not on branch personal"
# macOS privacy blocks xctest from reading ~/Documents, so the tests fail there with "Failed to create a bundle instance".
[[ $PWD != "$HOME"/Documents/* ]] || fail "repo is under ~/Documents; move it (e.g. to ~/Developer)"
check_running
echo "OK preflight"

# b. Sync with Upstream
git fetch upstream
if ! git merge --no-edit upstream/master; then
  git diff --name-only --diff-filter=U
  git merge --abort || true
  fail "merge conflict with upstream/master (files above); merge aborted"
fi
echo "OK merged upstream/master"
# The app crashes without a version, and PreferencesMigrations compares it with the stored preferencesVersion.
ver=$(git describe --tags --abbrev=0 --match 'v[0-9]*' HEAD | sed 's/^v//') # skip our personal-* rollback tags
[[ $ver =~ ^[0-9]+(\.[0-9]+)+$ ]] || fail "bad version from the latest tag: '$ver'"
echo "OK version $ver"
# A merge can move or drop the Release-only Pro switch without a conflict; never ship a build without it.
grep -q "Personal fork: Release always runs as Pro" src/pro/license/LicenseManager.swift \
  || fail "the Release Pro switch is missing from LicenseManager.computeState(); re-apply it"
echo "OK Pro switch present"

# c. Tests
ai/test.sh || fail "ai/test.sh failed"
echo "OK tests passed"

# d. Build (Release: -Osize, ThinLTO, stripped, no #if DEBUG code)
# config/local.xcconfig is upstream's gitignored per-developer override, included last by release.xcconfig and
# only by the app's own targets. Command-line signing settings would also hit the Swift packages, which then
# demand an Apple development team. Rewritten each run so the version follows the latest tag.
cat > config/local.xcconfig <<EOF
// Written by personal-build.sh on every run; edits are overwritten.
CODE_SIGN_IDENTITY = Local Self-Signed
OTHER_CODE_SIGN_FLAGS = --timestamp=none --deep --options runtime
CURRENT_PROJECT_VERSION = $ver
EOF
# shortcut: mirrors ai/build.sh's asset check and xcodebuild call (it takes no arguments), re-diff it on each sync.
# `clean`: incremental builds alternate between re-embedding Sparkle unsigned and re-signing it, because the
# "Copy Sparkle Helpers" phase doesn't list the embedded framework as an input. A clean build always runs both.
python3 scripts/assets/compile_illustrations.py --check || fail "asset check failed"
xcodebuild -project alt-tab-macos.xcodeproj -scheme Release -configuration Release -derivedDataPath DerivedData \
  clean build || fail "build failed"
built=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")
[[ $built == "$ver" ]] || fail "built app has version '$built', expected '$ver'"
echo "OK built $app (version $built)"

# e. Signature
codesign --verify --deep --strict "$app" || fail "codesign --verify failed"
sig=$(codesign -dv --verbose=2 "$app" 2>&1)
grep -qx 'Authority=Local Self-Signed' <<<"$sig" || fail "signature authority is not Local Self-Signed"
echo "OK signed: Authority=Local Self-Signed"

# f. Quit the running AltTab. check_running proves it is the only copy and the /Applications one, so the
# bundle-id quit (graceful: saves state) reaches it. osascript only when running: it would otherwise launch it.
check_running
if [[ -n $running ]]; then
  osascript -e 'tell application id "com.lwouis.alt-tab-macos" to quit'
  for _ in {1..10}; do kill -0 "$running" 2>/dev/null || break; sleep 1; done
  if kill -0 "$running" 2>/dev/null; then fail "AltTab (pid $running) still running after 10 seconds"; fi
fi
echo "OK AltTab not running"

# g. Back up the installed app as a zip: launchers and LaunchServices don't see an app inside a zip.
# Only the newest backup is kept; older ones and the replaced app go to the Trash, never rm.
stamp=$(date +%Y%m%d-%H%M%S)
backup=none
if [[ -e /Applications/AltTab.app ]]; then
  mkdir -p ~/AltTab-backups
  backup=~/AltTab-backups/AltTab-$stamp.zip
  ditto -c -k --keepParent /Applications/AltTab.app "$backup"
  unzip -tq "$backup" >/dev/null || fail "backup zip is unreadable: $backup"
  for old in ~/AltTab-backups/*; do [[ $old == "$backup" ]] || mv "$old" ~/.Trash/; done
  # LaunchServices keeps tracking the trashed copy (unregistering and renaming don't stick); emptying the Trash ends it.
  mv /Applications/AltTab.app ~/.Trash/AltTab-replaced-$stamp.app
fi
echo "OK backup: $backup"

# h. Install, and unregister the build copy so only /Applications/AltTab.app is launchable
ditto "$app" /Applications/AltTab.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/$app"
echo "OK installed /Applications/AltTab.app"

# i. Launch
open /Applications/AltTab.app
sleep 5
check_running
[[ -n $running ]] || fail "AltTab is not running after launch"
echo "OK AltTab running (one copy, pid $running)"

# Tag the good build: git is the real rollback (check out the tag and rebuild).
git tag "personal-$stamp"
echo "OK tagged personal-$stamp"

# j. Next steps
echo "Next: grant Accessibility and Screen Recording to AltTab in System Settings > Privacy & Security. Then open AltTab Settings, confirm Pro is on, and test search by typing in the switcher. Previous app backup: $backup (to roll back, follow \"Roll back\" in PERSONAL.md; never unzip over the installed app)."
