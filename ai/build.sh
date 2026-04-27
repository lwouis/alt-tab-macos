#!/usr/bin/env bash
# NOTE: First run will prompt for keychain password multiple times — click "Always Allow" each time.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$REPO_ROOT/DerivedData}"

xcodebuild \
  -workspace "$REPO_ROOT/alt-tab-macos.xcworkspace" \
  -scheme Debug \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA"
