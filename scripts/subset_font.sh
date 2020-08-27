#!/usr/bin/env bash

set -exu

"$(pipenv --venv)"/bin/pyftsubset resources/SF-Pro-Text-Regular-Full.otf \
  --output-file=resources/SF-Pro-Text-Regular.otf \
  --text="􀥃􀀁􀁎􀁌􀕧􀀸􀀺􀀼􀀾􀁀􀁂􀁄􀑱􀁆􀁈􀁊􀑳􀓵􀓶􀓷􀓸􀓹􀓺􀓻􀓼􀓽􀓾􀓿􀔀􀔁􀔂􀔃􀔄􀔅􀔆􀔇􀔈􀔉􀕬􀀹􀀻􀀽􀀿􀁁􀘘􀁃􀁅􀑲􀁇􀁉􀁋􀑴􀔔􀔕􀔖􀔗􀔘􀔙􀔚􀔛􀔜􀔝􀔞􀔟􀔠􀔡􀔢􀔣􀔤􀔥􀔦􀔧􀔨􀕭"
