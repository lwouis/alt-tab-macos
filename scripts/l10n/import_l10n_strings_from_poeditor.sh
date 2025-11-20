#!/usr/bin/env bash

set -exu

export readOnlyToken="8170d6b4f0531ffd7f52edea374a3689"
export projectId="316051"

function updateLanguageFile() {
  exportApiJson="$(curl -s -X POST https://api.poeditor.com/v2/projects/export \
    -d api_token="$readOnlyToken" \
    -d id="$projectId" \
    -d language="$1" \
    -d order="terms" \
    -d type="apple_strings" \
    -d 'filters=["translated"]')"
  fileUrl="$(jq -r '.result.url' <<<"$exportApiJson")"
  mkdir -p "resources/l10n/$1.lproj"
  curl -s "$fileUrl" | sed -e '/\/\*.*\*\//d' -e '/^$/d' -e '/ = "";$/d' > "resources/l10n/$1.lproj/Localizable.strings"
}

function getLanguagesOnPoeditor() {
  languagesOnPoeditor="$(curl -s -X POST https://api.poeditor.com/v2/languages/list \
    -d api_token="$readOnlyToken" \
    -d id="$projectId")"
  jq -r '.result.languages[] | select( .percentage != 0 ) | .code' <<<"$languagesOnPoeditor"
}

export -f updateLanguageFile
getLanguagesOnPoeditor | xargs -n 1 -P 20 -I {} bash -c 'updateLanguageFile "$@"' _ {}

# xcstrings
#
#exportApiJson="$(curl -s -X POST https://api.poeditor.com/v2/projects/export \
#  -d api_token="$readOnlyToken" \
#  -d id="$projectId" \
#  -d language="en" \
#  -d order="terms" \
#  -d type="xcstrings" \
#  -d 'filters=["translated"]' \
#  -d 'options=[{"export_all": 1}]')"
#fileUrl="$(jq -r '.result.url' <<<"$exportApiJson")"
#curl -s "$fileUrl" > "resources/l10n/Localizable.xcstrings"
