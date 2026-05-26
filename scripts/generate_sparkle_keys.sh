#!/usr/bin/env bash

set -euo pipefail

service="https://sparkle-project.org"
account="ed25519"
publicKey="$(Pods/Sparkle/bin/generate_keys -p 2>/dev/null | awk '/SUPublicEDKey to:/{getline; print; exit}')"
privateKey="$(security find-generic-password -s "$service" -a "$account" -w 2>/dev/null | tr -d '\n')"
if [[ -z "$publicKey" || -z "$privateKey" ]]; then
  echo "Run first: Pods/Sparkle/bin/generate_keys"
  exit 1
fi
if [[ ${#privateKey} -ne 128 ]]; then
  echo "Unexpected private key length (${#privateKey}, expected 128)"
  exit 1
fi
echo "SPARKLE_PUBLIC_KEY=$publicKey"
echo
echo "SPARKLE_ED_PRIVATE_KEY=$privateKey"
echo
echo "Add both as GitHub secrets in alt-alt-tab-macos → Settings → Secrets → Actions."
