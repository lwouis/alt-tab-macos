#!/usr/bin/env bash

set -exu

export readOnlyToken="8170d6b4f0531ffd7f52edea374a3689"
export projectId="316051"

function uploadLanguageFile() {
  curl -s -X POST https://api.poeditor.com/v2/projects/upload \
    -F api_token="$readWriteToken" \
    -F id="$projectId" \
    -F updating="translations" \
    -F language="$1" \
    -F file=@"resources/l10n/$1.lproj/Localizable.strings"
  sleep 20 # poeditor api rate-limit is 3 req/min
}

function getLanguagesOnPoeditor() {
  languagesOnPoeditor="$(curl -s -X POST https://api.poeditor.com/v2/languages/list \
    -d api_token="$readOnlyToken" \
    -d id="$projectId")"
  jq -r '.result.languages[] | select( .percentage != 0 ) | .code' <<<"$languagesOnPoeditor"
}

export -f uploadLanguageFile
getLanguagesOnPoeditor | xargs -n 1 -I {} bash -c 'uploadLanguageFile "$@"' _ {}
