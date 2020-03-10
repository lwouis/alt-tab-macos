#!/usr/bin/env bash

set -exu

version="$(cat $VERSION_FILE)"

/usr/local/Cellar/cask-repair --cask-version "$version" alt-tab
