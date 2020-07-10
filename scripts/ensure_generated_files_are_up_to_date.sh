set -exu

brew install jq
scripts/update_contributors.sh
scripts/import_l10n_strings_from_poeditor.sh
scripts/extract_l10n_strings.sh
# pod install

git status
git --no-pager diff
git diff-files --name-only --exit-code
