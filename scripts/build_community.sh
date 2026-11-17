#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/assets/compile_illustrations.py --check
xcodebuild \
  -project alt-tab-macos.xcodeproj \
  -scheme Release \
  -configuration Release \
  -derivedDataPath build/Community \
  CURRENT_PROJECT_VERSION=11.10.2.1 \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  OTHER_CODE_SIGN_FLAGS=--timestamp=none
