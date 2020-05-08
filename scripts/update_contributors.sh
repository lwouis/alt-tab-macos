#!/usr/bin/env bash

set -exu

readOnlyToken="8170d6b4f0531ffd7f52edea374a3689"
projectId="316051"

(
  echo -e "# Contributors\n"

  echo -e "They helped [develop the app](https://github.com/lwouis/alt-tab-macos/graphs/contributors):\n"

  curl https://api.github.com/repos/lwouis/alt-tab-macos/contributors |
    jq -r '.[]|("[" + .login + "](" + .html_url + ")")' |
    sed -e '/semantic-release-bot/d' |
    sort -f |
    sed -e 's/^/* /'

  echo -e "\nThey helped [localize the app](https://poeditor.com/join/project/8AOEZ0eAZE):\n"

  curl -s -X POST https://api.poeditor.com/v2/contributors/list \
    -d api_token="$readOnlyToken" \
    -d id="$projectId" |
    jq -r '.result.contributors[].name' |
    sort -f |
    sed -e 's/^/* /'
) >docs/CONTRIBUTORS.md
