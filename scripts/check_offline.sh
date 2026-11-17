#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -Wall -Wextra -Werror \
  -I src/vendors \
  src/vendors/OfflineSandbox.m scripts/tests/offline_sandbox_probe.c \
  -framework CoreFoundation -o build/offline_sandbox_probe
build/offline_sandbox_probe
