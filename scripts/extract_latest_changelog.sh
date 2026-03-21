#!/usr/bin/env bash

set -euo pipefail

# Write tag_name and release body to $GITHUB_OUTPUT for the GitHub release step
echo "tag_name=v$(cat "$VERSION_FILE")" >> "$GITHUB_OUTPUT"
echo "body<<EOF" >> "$GITHUB_OUTPUT"
awk '/^##? \[/{if(found) exit; found=1; next} found' docs/Changelog.md >> "$GITHUB_OUTPUT"
echo "EOF" >> "$GITHUB_OUTPUT"
