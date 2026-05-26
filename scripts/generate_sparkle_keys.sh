#!/usr/bin/env bash

set -euo pipefail

echo "1. Generate Sparkle keys (stored in macOS Keychain):"
echo "   Pods/Sparkle/bin/generate_keys"
echo
echo "2. Export the private key for GitHub Actions:"
echo "   Pods/Sparkle/bin/generate_keys -x /tmp/sparkle_ed_private_key.txt"
echo
echo "3. Print the public key for Info.plist / GitHub secret:"
echo "   Pods/Sparkle/bin/generate_keys -p"
echo
echo "4. Add GitHub secrets in alt-alt-tab-macos → Settings → Secrets → Actions:"
echo "   SPARKLE_PUBLIC_KEY=<output of step 3>"
echo "   SPARKLE_ED_PRIVATE_KEY=<contents of sparkle_ed_private_key.txt>"
echo
echo "5. Delete /tmp/sparkle_ed_private_key.txt after copying the secret."
