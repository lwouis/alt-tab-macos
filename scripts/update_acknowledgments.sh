#!/usr/bin/env bash

set -exu

(
  echo -e "# Acknowledgments\n"
  # remove incorrect whitespace from ShortcutRecorder license
  # remote first 2 lines (i.e. title)
  # force wrap text as some licenses are and some are not
  cat -s "Pods/Target Support Files/Pods-alt-tab-macos/Pods-alt-tab-macos-acknowledgements.markdown" |
    tail -n +2 |
    sed -e 's/^ \{12\}/      /' |
    sed -e 's/^ \{7\}/    /' |
    fold -w 80 -s
) >docs/Acknowledgments.md
