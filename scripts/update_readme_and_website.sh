#!/usr/bin/env bash

set -exu

version="$(cat "$VERSION_FILE")"
readOnlyToken="8170d6b4f0531ffd7f52edea374a3689"
projectId="316051"

github_api_request() {
  local url="$1"
  curl -s \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/lwouis/alt-tab-macos$url"
}

poeditor_api_request() {
  local url="$1"
  curl -s \
    -X POST \
    -d api_token="$readOnlyToken" \
    -d id="$projectId" \
    "https://api.poeditor.com/v2$url"
}

unicode_sort() {
  python3 -c 'import sys, unicodedata; print("".join(sorted((line for line in sys.stdin if line.strip()), key=lambda s: unicodedata.normalize("NFKD", s.casefold()))), end="")'
}

github_contributors() {
  github_api_request "/contributors" |
    jq -r '.[]|("[" + .login + "](" + .html_url + ")")' |
    sed -e '/semantic-release-bot/d' |
    unicode_sort |
    awk '{printf "%s%s", sep, $0; sep=", "} END{print ""}'
}

poeditor_contributors() {
  (
    echo "lwouis"
    poeditor_api_request "/contributors/list" |
      jq -r '.result.contributors[].name'
  ) |
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
    unicode_sort |
    awk '{printf "%s%s", sep, $0; sep=", "} END{print ""}'
}

generate_contributors() {
  echo "# Contributors"
  echo
  echo "## [Developed the app](https://github.com/lwouis/alt-tab-macos/graphs/contributors)"
  echo
  github_contributors
  echo
  echo "## [Localized the app](https://poeditor.com/join/project/8AOEZ0eAZE)"
  echo
  poeditor_contributors
}

get_total_downloads() {
  local downloads=0
  local page=1
  while true; do
    local response
    response=$(github_api_request "/releases?per_page=100&page=$page")
    # Safely sum all download counts, even if assets are empty
    local count
    count=$(echo "$response" | jq '[.[]?.assets[]?.download_count // 0] | add // 0')
    downloads=$((downloads + count))
    # Stop if no more releases
    if [[ $(echo "$response" | jq 'length') -lt 1 ]]; then
      break
    fi
    page=$((page + 1))
  done
  echo "$downloads"
}

get_stars() {
  github_api_request "" | jq '.stargazers_count'
}

format_number() {
  local NUM=$1
  if (( NUM >= 1000000 )); then
    printf "%.1fM" "$(echo "$NUM/1000000" | bc -l)"
  elif (( NUM >= 1000 )); then
    printf "%.0fK" "$(echo "$NUM/1000" | bc -l)"
  else
    printf "%d" "$NUM"
  fi
}

downloads=$(format_number "$(get_total_downloads)")
stars=$(format_number "$(get_stars)")
contributors=$(generate_contributors)

sed -i "" -E "s|(v)[^/]+(/AltTab-)[^/]+(\.zip)|\1${version}\2${version}\3|g" "README.md"
sed -i "" -E "s|(<sub>)[^ ]+( stars</sub>)|\1${stars}\2|g" "README.md"
sed -i "" -E "s|(<sub>)[^ ]+( downloads</sub>)|\1${downloads}\2|g" "README.md"
sed -i "" -E "s|(>)[^ ]+( downloads<)|\1${downloads}\2|g" "docs/_layouts/default.html"
echo "$contributors" > "docs/Contributors.md"
