#!/usr/bin/env bash

set -exu

version="$(cat $VERSION_FILE)"

scripts/cask-repair.sh --cask-version "$version" alt-tab
