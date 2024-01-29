#!/usr/bin/env bash

set -exu

fileDirectory="resources/l10n"
stringsFile="$fileDirectory/Localizable.strings"

rm $stringsFile
# generate fresh Localizable.strings
find src -name '*.swift' | xargs genstrings -a -o $fileDirectory
# convert to utf8
echo "$(iconv -f UTF-16LE -t UTF-8 $stringsFile)" > $stringsFile
file $stringsFile
# remove the BOM if there is one to be deterministic; iconv may add a BOM or not, depending on the platform
mv $stringsFile $stringsFile.tmp
sed $'1s/\xef\xbb\xbf//' < $stringsFile.tmp > $stringsFile
rm $stringsFile.tmp
file $stringsFile
