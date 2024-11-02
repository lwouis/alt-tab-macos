#!/usr/bin/env bash

set -ex

npm ci
if [ "$TRAVIS" = true ] ; then
  npx commitlint-travis
  npx commitlint
else
  npx commitlint --from "$GITHUB_EVENT_BEFORE" --to "$GITHUB_EVENT_AFTER" --verbose
fi
scripts/ensure_generated_files_are_up_to_date.sh
