#!/usr/bin/env bash

set -exu

version="$(cat VERSION.txt)"

cask-repair --cask-version "$version" alt-tab
