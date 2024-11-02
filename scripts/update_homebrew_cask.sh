#!/usr/bin/env bash

set -ex

version="$(cat $VERSION_FILE)"

brew bump-cask-pr --version $version alt-tab

#brew update
#brew install vitorgalvao/tiny-scripts/cask-repair
#
#if [ "$TRAVIS" = true ] ; then
#  # add github ssh key
#  echo "$GITHUB_SSH_KEY" | base64 --decode > github_ssh
#  chmod 600 github_ssh
#  ssh-add -K github_ssh
#fi
#
#cask-repair --blind-submit --cask-version "$version" alt-tab
