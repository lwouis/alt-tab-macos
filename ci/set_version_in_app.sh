#!/usr/bin/env bash

set -exu

version="$(cat VERSION.txt)"
# set the version for the app menubar menu text
sed -i '' -e "s/#VERSION#/$version/" alt-tab-macos/ui/StatusItem.swift
# set the version in the app meta-data for the AppStore and app "Get Info" panel
sed -i '' -e "s/#VERSION#/$version/" alt-tab-macos/Info.plist
