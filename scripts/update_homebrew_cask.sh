#!/usr/bin/env bash

set -exu

version="$(cat $VERSION_FILE)"

cask-repair --blind-submit --cask-version "$version" alt-tab
