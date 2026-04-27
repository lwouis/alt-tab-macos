#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$REPO_ROOT/DerivedData}"

xcodebuild \
  -workspace "$REPO_ROOT/alt-tab-macos.xcworkspace" \
  -scheme Debug \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA"
