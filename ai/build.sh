#!/bin/bash

xcodebuild \
  -workspace alt-tab-macos.xcworkspace \
  -scheme Debug \
  -configuration Debug \
  -derivedDataPath ~/git/alt-tab-macos/DerivedData
