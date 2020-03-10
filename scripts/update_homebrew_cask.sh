#!/usr/bin/env bash

set -exu

version="$(cat $VERSION_FILE)"

# add github ssh key
echo "$GITHUB_SSH_KEY" | base64 --decode > github_ssh
chmod 600 github_ssh
ssh-add -K github_ssh

cask-repair --blind-submit --cask-version "$version" alt-tab
