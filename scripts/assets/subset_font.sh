#!/usr/bin/env bash

set -exu

# Source font: developer machine's locally-installed SF Pro Text Regular from Apple's
# SF Symbols.app (https://developer.apple.com/sf-symbols/). Avoids tracking a 2 MB
# binary in the repo, and picks up Apple's latest glyph refinements automatically
# whenever the developer updates SF Symbols.app.
SOURCE_FONT=/Library/Fonts/SF-Pro-Text-Regular.otf
if [ ! -f "$SOURCE_FONT" ]; then
  echo "Missing $SOURCE_FONT — install SF Symbols.app from https://developer.apple.com/sf-symbols/" >&2
  exit 1
fi

# Characters MUST stay in sync with the `Symbols` enum in
# src/switcher/main-window/TileFontIconView.swift plus the 20 space-number variants
# synthesized at runtime in StatusIconsView.symbolForSpace.
"$(pipenv --venv)"/bin/pyftsubset "$SOURCE_FONT" \
  --output-file=resources/SF-Pro-Text-Regular.otf \
  --text="􀀁􀅴􀁎􀁌􀕧􀀸􀀺􀀼􀀾􀁀􀁂􀁄􀑱􀁆􀁈􀁊􀑳􀓵􀓶􀓷􀓸􀓹􀓺􀓻􀓼􀓽􀓾􀓿􀔀􀔁􀔂􀔃􀔄􀔅􀔆􀔇􀔈􀔉􀕬􀀹􀀻􀀽􀀿􀁁􀘘􀁃􀁅􀑲􀁇􀁉􀁋􀑴􀔔􀔕􀔖􀔗􀔘􀔙􀔚􀔛􀔜􀔝􀔞􀔟􀔠􀔡􀔢􀔣􀔤􀔥􀔦􀔧􀔨􀕭􀝥􀆔􀣋􀉻􀉣􀙠􀕾􀢹􀯔􀛭􀅼􀅽􀁏􀇰􀊛􀊫􁐎􁐏􁐐􀆿􀆭􀆺􀟛􀋃"
