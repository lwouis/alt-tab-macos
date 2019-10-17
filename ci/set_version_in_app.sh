#!/usr/bin/env bash

set -ex

version="$(cat VERSION.txt)"
sed -i '' -e "s/#VERSION#/$version/" alt-tab-macos/ui/Application.swift
