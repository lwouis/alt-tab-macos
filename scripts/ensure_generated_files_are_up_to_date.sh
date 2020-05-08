set -exu

pod install
scripts/extract_l10n_strings.sh
scripts/import_l10n_strings_from_poeditor.sh
scripts/update_contributors.sh

git status
git --no-pager diff
git diff-files --name-only --exit-code
