#!/usr/bin/env bash

set -exu

semanticRelease="$(npx semantic-release --dry-run --ci false 2>&1 || true)"
version="$(echo "$semanticRelease" | sed -nE 's/.+The next release version is (.+)/\1/p')"
if [[ -z "$version" ]]; then
  echo "No release required for this push"
  echo "skip=true" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi
echo "$version" > "$VERSION_FILE"
echo "version=$version" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "skip=false" >> "${GITHUB_OUTPUT:-/dev/null}"
