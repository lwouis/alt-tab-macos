#!/usr/bin/env bash

set -exu

fileDirectory="resources/l10n"
stringsFile="$fileDirectory/Localizable.strings"

rm $stringsFile
svgDirectory="$(mktemp -d "${TMPDIR:-/tmp}/alttab-svg-strings.XXXXXX")"
trap 'rm -rf "$svgDirectory"' EXIT
python3 scripts/l10n/svg_strings.py > "$svgDirectory/IllustrationStrings.swift"
# generate fresh Localizable.strings in a single genstrings run: a second run with -a appends keys it already wrote instead of merging them
{ find src -name '*.swift'; echo "$svgDirectory/IllustrationStrings.swift"; } | xargs genstrings -o $fileDirectory
# convert to utf8
echo "$(iconv -f UTF-16LE -t UTF-8 $stringsFile)" > $stringsFile
file $stringsFile
# remove the BOM if there is one to be deterministic; iconv may add a BOM or not, depending on the platform
mv $stringsFile $stringsFile.tmp
sed $'1s/\xef\xbb\xbf//' < $stringsFile.tmp > $stringsFile
rm $stringsFile.tmp
file $stringsFile
