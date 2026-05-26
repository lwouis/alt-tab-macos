#!/usr/bin/env bash

set -exu

version="$(cat "$VERSION_FILE")"
zipName="$APP_NAME-$version.zip"
zipPath="$BUILD_DIR/$XCODE_BUILD_PATH/$zipName"
sha256="$(shasum -a 256 "$zipPath" | awk '{print $1}')"
tapRepo="${HOMEBREW_TAP_REPO:-odrinateur/homebrew-altatltab}"
tapBranch="${HOMEBREW_TAP_BRANCH:-main}"
githubRepo="${GITHUB_REPOSITORY:-odrinateur/alt-alt-tab-macos}"
caskPath="Casks/altatltab.rb"
if [[ -z "${HOMEBREW_TAP_GITHUB_TOKEN:-}" ]]; then
  echo "HOMEBREW_TAP_GITHUB_TOKEN is required (PAT with Contents write on ${tapRepo})"
  exit 1
fi
export GH_TOKEN="$HOMEBREW_TAP_GITHUB_TOKEN"
canPush="$(gh api "repos/${tapRepo}" --jq '.permissions.push // false' 2>/dev/null || echo false)"
if [[ "$canPush" != "true" ]]; then
  echo "Token cannot push to ${tapRepo}. Create a classic PAT with repo scope, or a fine-grained PAT with Contents read/write on that repository, and set HOMEBREW_TAP_GITHUB_TOKEN."
  exit 1
fi
caskFile="$(mktemp)"
cat > "$caskFile" <<RUBY
cask "altatltab" do
  version "${version}"
  sha256 "${sha256}"

  url "https://github.com/${githubRepo}/releases/download/v#{version}/AltAtlTab-#{version}.zip",
      verified: "github.com/${githubRepo}/"
  name "AltAtlTab"
  desc "Windows-like alt-tab for macOS (AltTab fork)"
  homepage "https://github.com/${githubRepo}"

  livecheck do
    url :homepage
    strategy :github_latest
  end

  depends_on :macos

  app "AltAtlTab.app"

  uninstall quit: "com.local.altatltab"

  zap trash: [
    "~/Library/Application Support/com.local.altatltab",
    "~/Library/Caches/com.local.altatltab",
    "~/Library/HTTPStorages/com.local.altatltab",
    "~/Library/Preferences/com.local.altatltab.plist",
    "~/Library/LaunchAgents/com.local.altatltab.plist",
  ]
end
RUBY
existingSha="$(gh api "repos/${tapRepo}/contents/${caskPath}?ref=${tapBranch}" --jq .sha 2>/dev/null || true)"
contentBase64="$(base64 < "$caskFile" | tr -d '\n')"
apiArgs=(
  --method PUT
  "repos/${tapRepo}/contents/${caskPath}"
  -f message="Update AltAtlTab to ${version}"
  -f content="$contentBase64"
  -f branch="$tapBranch"
)
if [[ -n "$existingSha" ]]; then
  apiArgs+=(-f sha="$existingSha")
fi
gh api "${apiArgs[@]}"
