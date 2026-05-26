#!/usr/bin/env bash

set -exu

version="$(cat "$VERSION_FILE")"
zipName="$APP_NAME-$version.zip"
zipPath="$BUILD_DIR/$XCODE_BUILD_PATH/$zipName"
sha256="$(shasum -a 256 "$zipPath" | awk '{print $1}')"
tapRepo="${HOMEBREW_TAP_REPO:-odrinateur/homebrew-altatltab}"
tapBranch="${HOMEBREW_TAP_BRANCH:-main}"
githubRepo="${GITHUB_REPOSITORY:-odrinateur/alt-alt-tab-macos}"
tapDir="$(mktemp -d)"
git clone "https://x-access-token:${HOMEBREW_TAP_GITHUB_TOKEN}@github.com/${tapRepo}.git" "$tapDir"
cd "$tapDir"
git checkout "$tapBranch" 2>/dev/null || git checkout -b "$tapBranch"
mkdir -p Casks
cat > Casks/altatltab.rb <<RUBY
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

  depends_on macos: ">= :sierra"

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
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add Casks/altatltab.rb
git diff --staged --quiet && exit 0
git commit -m "Update AltAtlTab to ${version}"
git push origin "HEAD:${tapBranch}"
