#!/usr/bin/env bash

set -exu

github_api_request() {
  local url="$1"
  curl -s \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/lwouis/alt-tab-macos$url"
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

# Rewrite only the "Developed the app" section of docs/contributors.md, preserving the
# frozen "Localized the app" section below it.
update_developer_contributors() {
  local file="docs/contributors.md"
  {
    echo "## [Developed the app](https://github.com/lwouis/alt-tab-macos/graphs/contributors)"
    echo
    github_contributors
    echo
    sed -n '/## Localized the app/,$p' "$file"
  } > "$file.tmp" && mv "$file.tmp" "$file"
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

# Stats are baked into docs/readme/main.svg (one consolidated SVG that holds
# the hero, stats, CTAs, and screenshot). Each stat text element is preceded by
# an XML comment marker — anchor sed on the marker and replace whatever value
# follows up to the next `<` (i.e. the closing `</text>`).
sed -i "" -E "s|(<!--downloads-->)[^<]*|\1${downloads}|" "docs/readme/main.svg"
sed -i "" -E "s|(<!--stars-->)[^<]*|\1${stars}|" "docs/readme/main.svg"

update_developer_contributors
