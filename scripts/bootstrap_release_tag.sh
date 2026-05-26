#!/usr/bin/env bash

set -euo pipefail

tag="${1:-v10.12.0}"
git tag -a "$tag" -m "Bootstrap release versioning at ${tag#v}"
echo "Created tag $tag"
echo "Push it with: git push origin $tag"
