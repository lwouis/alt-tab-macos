#!/usr/bin/env bash

set -ex

version="$(cat VERSION.txt)"

cask-repair --cask-version "$version" alt-tab
