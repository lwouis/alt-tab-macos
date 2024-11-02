#!/usr/bin/env bash

set -ex

brew update
brew install vitorgalvao/tiny-scripts/cask-repair

version="$(cat $VERSION_FILE)"

if [ "$TRAVIS" = true ] ; then
  # add github ssh key
  echo "$GITHUB_SSH_KEY" | base64 --decode > github_ssh
  chmod 600 github_ssh
  ssh-add -K github_ssh
fi

cask-repair --blind-submit --cask-version "$version" alt-tab
