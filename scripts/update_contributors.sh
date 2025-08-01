#!/usr/bin/env bash

set -exu

readOnlyToken="8170d6b4f0531ffd7f52edea374a3689"
projectId="316051"

function unicode_sort() {
  python3 -c 'import sys, unicodedata; print("".join(sorted((line for line in sys.stdin if line.strip()), key=lambda s: unicodedata.normalize("NFKD", s.casefold()))), end="")'
}

(
  echo -e "# Contributors\n"

  echo -e "They helped [develop the app](https://github.com/lwouis/alt-tab-macos/graphs/contributors):\n"

  # this script is ran on shared CI machines which go over github's quota
  # thus we use a token here to guaranty that the call will succeed
  curl https://api.github.com/repos/lwouis/alt-tab-macos/contributors \
    -H "Authorization: token $GITHUB_TOKEN" |
    jq -r '.[]|("[" + .login + "](" + .html_url + ")")' |
    sed -e '/semantic-release-bot/d' |
    unicode_sort |
    sed -e 's/^/* /'

  echo -e "\nThey helped [localize the app](https://poeditor.com/join/project/8AOEZ0eAZE):\n"

  (
    echo -e "lwouis"
    curl -s -X POST https://api.poeditor.com/v2/contributors/list \
      -d api_token="$readOnlyToken" \
      -d id="$projectId" |
      jq -r '.result.contributors[].name'
  ) |
    unicode_sort |
    sed -e 's/^/* /'
) >docs/Contributors.md
