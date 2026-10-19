#!/bin/bash

python3 scripts/l10n/validate_localizations.py || exit $?
python3 scripts/assets/compile_illustrations.py --check || exit $?
python3 scripts/assets/test_compile_illustrations.py || exit $?

# The `Test` scheme's own TestAction targets Debug; only CI (scripts/run_tests.sh) overrides it to
# Release. Release means wholemodule + -Osize, so ANY edit to a shared source recompiles all 131 files of
# the test target: measured 34s vs 1.3s here, to buy 1.7s less runtime (8.8s vs 10.8s). Debug also
# runs the `#if DEBUG` tests that Release drops.
xcodebuild test \
  -project alt-tab-macos.xcodeproj \
  -scheme Test \
  -configuration Debug \
  -derivedDataPath DerivedData
