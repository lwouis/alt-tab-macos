#!/bin/bash

# The `Test` scheme's own TestAction targets Debug; only CI (scripts/run_tests.sh) overrides it to
# Release. Release means wholemodule + -O, so ANY edit to a shared source recompiles all 131 files of
# the test target: measured 34s vs 1.3s here, to buy 1.7s less runtime (8.8s vs 10.8s). Debug also
# runs the `#if DEBUG` tests that Release drops.
xcodebuild test \
  -project alt-tab-macos.xcodeproj \
  -scheme Test \
  -configuration Debug \
  -derivedDataPath DerivedData
