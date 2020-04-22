#!/usr/bin/env bash

set -exu

fileDirectory="resources/l10n"
readOnlyToken="8170d6b4f0531ffd7f52edea374a3689"
projectId="316051"

function updateLanguageFile() {
  exportApiJson="$(curl -X POST https://api.poeditor.com/v2/projects/export \
    -d api_token="$readOnlyToken" \
    -d id="$projectId" \
    -d language="$1" \
    -d order="terms" \
    -d type="apple_strings")"
  fileUrl="$(jq -r '.result.url' <<<"$exportApiJson")"
  curl "$fileUrl" > "$fileDirectory/$1.lproj/Localizable.strings"
}

function getLanguagesOnPoeditor() {
  languagesOnPoeditor="$(curl -X POST https://api.poeditor.com/v2/languages/list \
    -d api_token="$readOnlyToken" \
    -d id="$projectId")"
  jq -r .result.languages[].code <<<"$languagesOnPoeditor"
}

for language in $(getLanguagesOnPoeditor); do
  updateLanguageFile "$language" &
done
