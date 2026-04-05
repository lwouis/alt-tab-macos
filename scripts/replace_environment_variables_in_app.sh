#!/usr/bin/env bash

set -exu

# Inject CI values via the same xcconfig override mechanism used locally.
# Xcode substitutes $(VAR) refs into Info.plist at build time.
cat > config/local.xcconfig <<EOF
CURRENT_PROJECT_VERSION = $(cat "$VERSION_FILE")
APPCENTER_SECRET = $APPCENTER_SECRET
EOF
