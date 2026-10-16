#!/bin/bash

python3 scripts/assets/compile_illustrations.py --check || exit $?

xcodebuild \
  -project alt-tab-macos.xcodeproj \
  -scheme Debug \
  -configuration Debug \
  -derivedDataPath DerivedData
