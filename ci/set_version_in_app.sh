#!/usr/bin/env bash

set -exu

version="$(cat VERSION.txt)"
# set the version displayed in the app UI
sed -i '' -e "s/#VERSION#/$version/" alt-tab-macos/ui/App.swift
# set the version in the app meta-data for the AppStore and app "Get Info" panel
sed -i '' -e "s/#VERSION#/$version/" alt-tab-macos/Info.plist
