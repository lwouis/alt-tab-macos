#!/usr/bin/env bash

set -exu

fileDirectory="resources/l10n"
stringsFile="$fileDirectory/Localizable.strings"

convertFile() {
  echo "$(iconv -f $1 -t $2 $stringsFile)" > $stringsFile
}

rm $stringsFile
find src -name '*.swift' | xargs genstrings -a -o $fileDirectory
convertFile UTF-16LE UTF-8
