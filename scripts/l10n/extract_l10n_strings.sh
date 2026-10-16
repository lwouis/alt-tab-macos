#!/usr/bin/env bash

set -exu

fileDirectory="resources/l10n"
stringsFile="$fileDirectory/Localizable.strings"

rm $stringsFile
# generate fresh Localizable.strings
find src -name '*.swift' | xargs genstrings -a -o $fileDirectory
svgDirectory="$(mktemp -d "${TMPDIR:-/tmp}/alttab-svg-strings.XXXXXX")"
trap 'rm -rf "$svgDirectory"' EXIT
python3 scripts/l10n/svg_strings.py > "$svgDirectory/IllustrationStrings.swift"
genstrings -a -o "$fileDirectory" "$svgDirectory/IllustrationStrings.swift"
# convert to utf8
echo "$(iconv -f UTF-16LE -t UTF-8 $stringsFile)" > $stringsFile
file $stringsFile
# remove the BOM if there is one to be deterministic; iconv may add a BOM or not, depending on the platform
mv $stringsFile $stringsFile.tmp
sed $'1s/\xef\xbb\xbf//' < $stringsFile.tmp > $stringsFile
rm $stringsFile.tmp
file $stringsFile
