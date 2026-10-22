#!/usr/bin/env bash

set -ex

buildLog=$(mktemp)

cleanupBuildDiagnostics() {
  if [[ -n ${buildDiagnosticsPid:-} ]]; then
    pkill -P "$buildDiagnosticsPid" 2>/dev/null || true
    kill "$buildDiagnosticsPid" 2>/dev/null || true
  fi
  rm -f "$buildLog"
}

reportBuildProgress() {
  echo '::group::Release build process diagnostics'
  awk '/^(SwiftCompile|SwiftEmitModule|CompileC|Ld |CodeSign|GenerateDSYMFile|ProcessInfoPlistFile|PhaseScriptExecution|Touch )/ { print substr($0, 1, 300) }' "$buildLog" | tail -n 12
  ps -axo pid,ppid,etime,%cpu,rss,comm | awk 'NR == 1 || /swift-frontend|clang|\/ld$|xcodebuild|codesign|xcbeautify|[XS]CBBuildService|SWBBuildService/'
  sysctl hw.memsize vm.swapusage
  for buildProcessPid in $(pgrep -x 'swift-frontend|clang|ld|xcodebuild|codesign|xcbeautify|XCBBuildService|SWBBuildService' || true); do
    sampleFile="${TMPDIR:-/tmp}/alttab-build-$buildProcessPid.sample.txt"
    sample "$buildProcessPid" 1 1 -file "$sampleFile" >/dev/null 2>&1 || true
    if [[ -f "$sampleFile" ]]; then sed -n '1,160p' "$sampleFile"; fi
  done
  echo '::endgroup::'
}

trap cleanupBuildDiagnostics EXIT
if [[ ${CI:-} == true ]]; then
  (while sleep 180; do reportBuildProgress; done) &
  buildDiagnosticsPid=$!
fi

set -o pipefail && xcodebuild -project alt-tab-macos.xcodeproj -scheme Release -derivedDataPath DerivedData | tee "$buildLog" | scripts/xcbeautify
file "$BUILD_DIR/$XCODE_BUILD_PATH/$APP_NAME.app/Contents/MacOS/$APP_NAME"
