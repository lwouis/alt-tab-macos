#!/usr/bin/env bash

set -exu

version="$(cat $VERSION_FILE)"

cask-repair --cask-version "$version" alt-tab
