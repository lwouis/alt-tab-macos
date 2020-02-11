#!/usr/bin/env bash

set -exu

semanticRelease=$(npx semantic-release --dry-run --ci false)
version=$(echo "$semanticRelease" | sed -nE 's/.+The next release version is (.+)/\1/p')
changelogDelta=$(echo "$semanticRelease" | sed -n '/Release note for version/,$p' | sed '1d')

echo "$version" > VERSION.txt
echo "$changelogDelta" > CHANGELOG_DELTA.txt
