set -ex

scripts/update_contributors.sh
#scripts/l10n/import_l10n_strings_from_poeditor.sh
scripts/l10n/extract_l10n_strings.sh
#pod install

git status
git --no-pager diff
git diff-files --name-only --exit-code
