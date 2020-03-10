#!/usr/bin/env bash

# downloaded from https://github.com/vitorgalvao/tiny-scripts/blob/master/cask-repair

readonly program="$(basename "${0}")"
export readonly MACOS_VERSION='10.15' # Latest macOS version, so commands like `fetch` are not dependent on the contributor’s OS
readonly submit_pr_to='homebrew:master'
readonly caskroom_origin_remote_regex='(https://|(ssh://)?git@)github.com[/:]Homebrew/homebrew-cask'
readonly caskroom_taps=(cask cask-versions cask-fonts cask-drivers)
readonly caskroom_taps_dir="$(brew --repository)/Library/Taps/homebrew"
readonly user_agent=(--user-agent 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10) https://brew.sh')
readonly hub_config="${HOME}/.config/hub"
readonly github_username="${GITHUB_USER:-$(awk '/user:/{print $(NF)}' "${hub_config}" 2>/dev/null | head -1)}"
readonly cask_repair_remote_name="${github_username}"
readonly cask_repair_branch_prefix='cask_repair_update'
readonly submission_error_log="$(mktemp)"

show_home='false' # By default, do not open the cask's homepage
show_appcast='false' # By default, do not open the cask's appcast
warning_messages=()
has_errors=''

function color_message {
  local color="${1}"
  local message="${2}"
  local -r all_colors=('black' 'red' 'green' 'yellow' 'blue' 'magenta' 'cyan' 'white')

  for i in "${!all_colors[@]}"; do
    if [[ "${all_colors[${i}]}" == "${color}" ]]; then
      local color_index="${i}"
      echo -e "$(tput setaf "${i}")${message}$(tput sgr0)"
      break
    fi
  done

  if [[ -z "${color_index}" ]]; then
    echo "${FUNCNAME[0]}: '${color}' is not a valid color."
    exit 1
  fi
}

function failure_message {
  color_message 'red' "${1}" >&2
}

function success_message {
  color_message 'green' "${1}"
}

function warning_message {
  color_message 'yellow' "${1}"
}

function syntax_error {
  abort "${program}: ${1}\nTry \`${program} --help\` for more information."
}

function push_failure_message {
  warning_message 'There were errors while pushing:'
  echo "${1}"
  abort 'Please fix the errors and try again. If the issue persists, open a bug report on the repo for this script (https://github.com/vitorgalvao/tiny-scripts).'
}

function require_hub {
  if ! command -v 'hub' &>/dev/null; then
    warning_message '`hub` was not found. Installing it…'
    brew install hub
  fi

  if [[ -z "${github_username}" ]] || [[ -z "${GITHUB_TOKEN}" && ! $(grep 'oauth_token:' "${hub_config}" 2>/dev/null) ]]; then
    abort '`hub` is not configured.\nTo do it, run `(cd $(brew --repository) && hub issue)`. Your Github password will be required, but is never stored.'
  fi
}

function usage {
  echo "
    Usage:
      ${program} [options] <cask_name>

    Options:
      -o, --open-home                        Open the homepage for the given cask.
      -a, --open-appcast                     Open the appcast for the given cask.
      -v, --cask-version                     Give a version directly, instead of being prompted for it.
      -u, --cask-url                         Give a URL directly, instead of being prompted for it.
      -e, --edit-cask                        Opens cask for editing before trying first download.
      -c <number>, --closes-issue <number>   Adds 'Closes #<number>.' to the pull request.
      -m <message>, --message <message>      Adds '<message>' to the pull request.
      -r, --reword                           Open commit message editor before committing.
      -b, --blind-submit                     Submit cask without asking for confirmation, if there are no errors.
      -f, --fail-on-error                    If there are any errors with the submission, abort.
      -w, --fail-on-warning                  If there are any warnings or errors with the submission, abort.
      -i, --install-cask                     Installs your updated cask after submission.
      -d, --delete-branches                  Deletes all local and remote branches named like ${cask_repair_branch_prefix}-<word>.
      -h, --help                             Show this help.
  " | sed -E 's/^ {4}//'
}

function current_origin {
  git remote get-url origin
}

function current_tap {
  basename "$(current_origin)" '.git'
}

function ensure_caskroom_repos {
  local current_caskroom_taps

  current_caskroom_taps=($(HOMEBREW_NO_AUTO_UPDATE=1 brew tap | grep '^homebrew/cask' | sed 's|^homebrew/|homebrew-|'))

  for repo in "${caskroom_taps[@]}"; do
    if grep --silent "${repo}" <<< "${current_caskroom_taps[@]}"; then
      continue
    else
      warning_message "\`homebrew/${repo}\` not tapped. Tapping…"
      HOMEBREW_NO_AUTO_UPDATE=1 brew tap "homebrew/${repo}"
    fi
  done
}

function cd_to_cask_tap {
  local cask_file cask_file_location

  cask_file="${1}"

  cask_file_location="$(find "${caskroom_taps_dir}" -path "*/Casks/${cask_file}")"
  [[ -z "${cask_file_location}" ]] && abort "No such cask was found in any official repo (${cask_name})."
  cd "$(dirname "${cask_file_location}")" || abort "Failed to change to directory of ${cask_file}."
}

function require_correct_origin {
  local origin_remote

  origin_remote="$(current_origin)"

  grep --silent --ignore-case --extended-regexp "^${caskroom_origin_remote_regex}" <<< "${origin_remote}" || abort "\`origin\` is pointing to an incorrect remote (${origin_remote}). Its beginning must match ${caskroom_origin_remote_regex}."
}

function ensure_cask_repair_remote {
  if ! git remote | grep --silent "${cask_repair_remote_name}"; then
    warning_message "A \`${cask_repair_remote_name}\` remote does not exist. Creating it now…"

    hub fork
  fi
}

function http_status_code {
  local url follow_redirects

  url="${1}"
  [[ "${2}" == 'follow_redirects' ]] && follow_redirects='--location' || follow_redirects='--no-location'

  curl --silent --head "${follow_redirects}" "${user_agent[@]}" --write-out '%{http_code}' "${url}" --output '/dev/null'
}

function has_interpolation {
  local version="${1}"

  [[ "${version}" =~ \#{version.*} ]]
}

function is_version_latest {
  local cask_file="${1}"

  [[ "$(brew cask _stanza version "${cask_file}")" == 'latest' ]]
}

function has_block_url {
  local cask_file="${1}"

  grep --silent 'url do' "${cask_file}"
}

function has_language_stanza {
  local cask_file="${1}"

  brew cask _stanza language "${cask_file}" 2>/dev/null
}

function modify_stanza {
  local stanza_to_modify new_stanza_value cask_file stanza_match_regex last_stanza_match stanza_start ending_comma

  stanza_to_modify="${1}"
  new_stanza_value="${2}"
  cask_file="${3}"

  stanza_match_regex="^\s*${stanza_to_modify} "
  last_stanza_match="$(grep "${stanza_match_regex}" "${cask_file}" | tail -1)"
  stanza_start="$(/usr/bin/perl -pe "s/(${stanza_match_regex}).*/\1/" <<< "${last_stanza_match}")"
  if grep --quiet ',$' <<< "${last_stanza_match}"; then
    ending_comma=','
  fi

  /usr/bin/perl -0777 -i -e'
    $last_stanza_match = shift(@ARGV);
    $stanza_start = shift(@ARGV);
    $new_stanza_value = shift(@ARGV);
    $ending_comma = shift(@ARGV);
    print <> =~ s|\Q$last_stanza_match\E|$stanza_start$new_stanza_value$ending_comma|r;
  ' "${last_stanza_match}" "${stanza_start}" "${new_stanza_value}" "${ending_comma}" "${cask_file}"
}

function modify_url {
  local url cask_file

  url="${1}"
  cask_file="${2}"

  # Use appropriate quotes depending on if a url with interpolation was given
  if has_interpolation "${url}"; then
    modify_stanza 'url' "\"${url}\"" "${cask_file}"
  else
    modify_stanza 'url' "'${url}'" "${cask_file}"
  fi
}

function appcast_url {
  local cask_file="${1}"

  brew cask _stanza appcast "${cask_file}"
}

function has_appcast {
  local cask_file="${1}"

  [[ -n "$(appcast_url "${cask_file}" 2>/dev/null)" ]]
}

function sha_change {
  local cask_sha_deliberatedly_unchecked downloaded_file package_sha cask_file

  cask_file="${1}"

  cask_sha_deliberatedly_unchecked="$(grep 'sha256 :no_check # required as upstream package is updated in-place' "${cask_file}")"
  [[ -n "${cask_sha_deliberatedly_unchecked}" ]] && return # Abort function if cask deliberately uses :no_check with a version

  # Set sha256 as :no_check temporarily, to prevent mismatch errors when fetching
  modify_stanza 'sha256' ':no_check' "${cask_file}"

  if ! brew cask fetch --force "${cask_file}"; then
    clean
    abort "There was an error fetching ${cask_file}. Please check your connection and try again."
  fi
  downloaded_file=$(brew cask fetch "${cask_file}" 2>/dev/null | tail -1 | sed 's/==> Success! Downloaded to -> //')
  package_sha=$(shasum --algorithm 256 "${downloaded_file}" | awk '{ print $1 }')

  modify_stanza 'sha256' "'${package_sha}'" "${cask_file}"
}

function delete_created_branches {
  local local_branches remote_branches

  for dir in "${caskroom_taps_dir}/homebrew-cask"*; do
    cd "${dir}" || abort "Failed to delete branches. ${dir} does not exist."

    if git remote | grep --silent "${cask_repair_remote_name}"; then # Proceed only if the correct remote exists
      # Delete local branches
      local_branches=$(git branch --all | grep --extended-regexp "^ *${cask_repair_branch_prefix}-.+$" | /usr/bin/perl -pe 's|^ *||;s|\n| |')
      [[ -n "${local_branches}" ]] && git branch -D ${local_branches}

      # Delete remote branches
      git fetch --prune "${cask_repair_remote_name}"
      remote_branches=$(git branch --all | grep --extended-regexp "remotes/${cask_repair_remote_name}/${cask_repair_branch_prefix}-.+$" | /usr/bin/perl -pe 's|.*/||;s|\n| |')
      [[ -n "${remote_branches}" ]] && git push "${cask_repair_remote_name}" --delete ${remote_branches}
    fi

    cd ..
  done
}

function edit_cask {
  local cask_file found_editor

  cask_file="${1}"

  echo 'Opening cask in default editor. If it is a GUI editor, you will need to completely quit it (⌘Q) before the script can continue.'

  for text_editor in {"${HOMEBREW_EDITOR}","${EDITOR}","${GIT_EDITOR}"}; do
    if [[ -n "${text_editor}" ]]; then
      eval "${text_editor}" "${cask_file}"
      found_editor='true'
      break
    fi
  done

  [[ -n "${found_editor}" ]] || open -W "${cask_file}"
}

function add_warning {
  local message severity color

  severity="${1}"
  message="$(sed '/./,$!d' <<< "${2}")" # Remove leading blank lines, so audit errors related to ruby still show

  if [[ "${severity}" == 'warning' ]]; then
    color="$(tput setaf 3)•$(tput sgr0)"
  else
    color="$(tput setaf 1)•$(tput sgr0)"
    has_errors='true'
  fi

  warning_messages+=("${color} ${message}")
}

function show_warnings {
  if [[ "${#warning_messages[@]}" -gt 0 ]]; then
    printf '%s\n' "${warning_messages[@]}" >&2
    divide
  fi
}

function clear_warnings {
  warning_messages=()
  unset has_errors
}

function lock {
  local lock_file action
  readonly lock_file='/tmp/cask-repair.lock'
  readonly action="${1}"

  if [[ "${action}" == 'create' ]]; then
    touch "${lock_file}"
  elif [[ "${action}" == 'exists?' ]]; then
    [[ -f "${lock_file}" ]] && return 0 || return 1
  elif [[ "${action}" == 'remove' ]]; then
    [[ -f "${lock_file}" ]] && rm "${lock_file}"
  fi
}

function clean {
  local current_branch

  lock 'remove'

  [[ "$(dirname "$(dirname "${PWD}")")" == "${caskroom_taps_dir}" ]] || return # Do not try to clean if not in a tap dir (e.g. if script was manually aborted too fast)

  current_branch="$(git rev-parse --abbrev-ref HEAD)"

  git reset HEAD --hard --quiet
  git checkout master --quiet
  git branch -D "${current_branch}" --quiet
  [[ -f "${submission_error_log}" ]] && rm "${submission_error_log}"
  unset given_cask_version given_cask_url cask_updated
}

function skip {
  clean
  echo -e "${1}"
}

function abort {
   clean
   failure_message "\n${1}\n"
   exit 1
 }

trap 'abort "You aborted."' SIGINT

function divide {
  command -v 'hr' &>/dev/null && hr - || echo '--------------------'
}

# Available flags
args=()
while [[ "${1}" ]]; do
  case "${1}" in
    -h | --help)
      usage
      exit 0
      ;;
    -o | --open-home)
      show_home='true'
      ;;
    -a | --open-appcast)
      show_appcast='true'
      ;;
    -v | --cask-version)
      given_cask_version="${2}"
      shift
      ;;
    -u | --cask-url)
      given_cask_url="${2}"
      shift
      ;;
    -e | --edit-cask)
      edit_on_start='true'
      ;;
    -c | --closes-issue)
      issue_to_close="${2}"
      shift
      ;;
    -m | --message)
      extra_message="${2}"
      shift
      ;;
    -r | --reword)
      reword_commit='true'
      ;;
    -b | --blind-submit)
      updated_blindly='true'
      ;;
    -f | --fail-on-error)
      abort_on_error='true'
      ;;
    -w | --fail-on-warning)
      abort_on_error='true'
      abort_on_warning='true'
      ;;
    -i | --install-cask)
      install_now='true'
      ;;
    -d | --delete-branches)
      can_run_without_arguments='true'
      delete_created_branches='true'
      ;;
    --)
      shift
      args+=("${@}")
      break
      ;;
    -*)
      syntax_error "Unrecognised option: ${1}"
      ;;
    *)
      args+=("${1}")
      ;;
  esac
  shift
done
set -- "${args[@]}"

# Exit if no argument or more than one argument was given
if [[ -z "${1}" && "${can_run_without_arguments}" != 'true' ]]; then
  usage
  exit 1
fi

if [[ "${delete_created_branches}" == 'true' ]]; then
  delete_created_branches
  exit 0
fi

# Only allow one instance at a time
if lock 'exists?'; then
  # We want this to be different from abort, so as to not remove the lock file
  failure_message "Only one ${program} instance can be run at once."
  exit 1
else
  lock 'create'
fi

require_hub
ensure_caskroom_repos

if [[ -z "${HOMEBREW_NO_AUTO_UPDATE}" ]]; then
  brew update
  echo -n 'Updating taps… '
else
  warning_message "You have set 'HOMEBREW_NO_AUTO_UPDATE'. If ${program} fails, unset it and retry your command before submitting a bug report."
fi

for cask in "${@}"; do
  # Clean the cask's name, and check if it is valid
  cask_name="${cask%.rb}" # Remove '.rb' extension, if present
  cask_file="./${cask_name}.rb"
  cask_branch="${cask_repair_branch_prefix}-${cask_name}"

  cd_to_cask_tap "${cask_name}.rb"
  require_correct_origin
  ensure_cask_repair_remote

  has_language_stanza "${cask_file}" && abort "${cask_name} has a language stanza. It cannot be updated via this script. Try update_multilangual_casks: https://github.com/Homebrew/homebrew-cask/blob/master/developer/bin/update_multilangual_casks"

  git rev-parse --verify "${cask_branch}" &>/dev/null && git checkout "${cask_branch}" master --quiet || git checkout -b "${cask_branch}" master --quiet # Create branch or checkout if it already exists

  # Open home and appcast
  [[ "${show_home}" == 'true' ]] && brew cask home "${cask_file}"

  if has_appcast "${cask_file}"; then
    cask_appcast_url="$(appcast_url "${cask_file}")"

    if [[ "${show_appcast}" == 'true' ]]; then
      [[ "${cask_appcast_url}" =~ ^https://github.com.*releases.atom$ ]] && open "${cask_appcast_url%.atom}" || open "${cask_appcast_url}" # if appcast is from github releases, open the page instead of the feed
    fi
  fi

  # Show cask's current state
  divide
  cat "${cask_file}"
  divide

  # Save old cask version
  old_cask_version="$(brew cask _stanza version "${cask_file}")"

  # Set cask version
  if [[ -z "${given_cask_version}" ]]; then
    read -rp $'Type the new version (or leave blank to use current one, or use `s` to skip)\n> ' given_cask_version # Ask for cask version, if not given previously

    if [[ "${given_cask_version}" == 's' ]]; then
      skip 'Skipping…'
      continue
    fi

    [[ -z "${given_cask_version}" ]] && given_cask_version=$(brew cask _stanza version "${cask_file}")
  fi

  if [[ "${given_cask_version}" == ':latest' || "${given_cask_version}" == 'latest' ]]; then # Allow both ':latest' and 'latest' to be given
    modify_stanza 'version' ':latest' "${cask_file}"
  else
    modify_stanza 'version' "'${given_cask_version}'" "${cask_file}"
  fi

  if [[ -n "${given_cask_url}" ]]; then
    if has_block_url "${cask_file}"; then
      warning_message 'Cask has block url, so it can only be modified manually (choose `[e]dit` when prompted).'
    else
      modify_url "${given_cask_url}" "${cask_file}"
    fi
  else
    # If url does not use interpolation and is not block, ask for it
    cask_bare_url=$(grep "url ['\"].*['\"]" "${cask_file}" | sed -E "s|.*url ['\"](.*)['\"].*|\1|")
    if ! has_interpolation "${cask_bare_url}" && ! has_block_url "${cask_file}"; then
      read -rp $'Paste the new URL (or leave blank to use the current one)\n> ' given_cask_url

      [[ -n "${given_cask_url}" ]] && modify_url "${given_cask_url}" "${cask_file}"
    fi

    cask_url=$(brew cask _stanza url "${cask_file}")

    # Check if the URL sends a 200 HTTP code, else abort
    cask_url_status=$(http_status_code "${cask_url}" 'follow_redirects')

    [[ "${cask_url}" =~ (github.com|bitbucket.org) ]] && cask_url_status='200' # If the download URL is from github or bitbucket, fake the status code

    if [[ "${cask_url_status}" != '200' ]]; then
      [[ -z "${cask_url_status}" ]] && add_warning warning 'you need to use a valid URL' || add_warning warning "url is probably incorrect, as a non-200 (OK) HTTP response code was returned (${cask_url_status})"
    fi
  fi

  [[ "${edit_on_start}" == 'true' ]] && edit_cask "${cask_file}"

  if is_version_latest "${cask_file}"; then
    modify_stanza 'sha256' ':no_check' "${cask_file}"
  else
    sha_change "${cask_file}"
  fi

  # Check if everything is alright, else abort
  [[ -z "${cask_updated}" ]] && cask_updated='false'
  until [[ "${cask_updated}" =~ ^[yne]$ ]]; do
    # fix style errors and check for style and audit errors
    style_message=$(brew cask style --fix "${cask_file}" 2>/dev/null)
    style_result="${?}"
    [[ "${style_result}" -ne 0 ]] && add_warning error "${style_message}"

    audit_message=$(brew cask audit "${cask_file}" 2>/dev/null)
    audit_result="${?}"
    [[ "${audit_result}" -ne 0 ]] && add_warning error "${audit_message}"

    git --no-pager diff
    divide
    show_warnings
    [[ -n "${abort_on_error}" && "${has_errors}" == 'true' ]] && abort 'The submission has errors and you elected to abort on those cases.'
    [[ -n "${abort_on_warning}" && "${#warning_messages[@]}" -gt 0 ]] && abort 'The submission has warnings and you elected to abort on those cases.'

    if [[ -n "${updated_blindly}" && "${#warning_messages[@]}" -eq 0 ]]; then
      cask_updated='y'
    else
      read -rn1 -p 'Is everything correct? ([y]es / [n]o / [e]dit) ' cask_updated
      echo # Add an empty line
    fi

    if [[ "${cask_updated}" == 'y' ]]; then
      if [[ "${style_result}" -ne 0 || "${audit_result}" -ne 0 ]]; then
        cask_updated='false'
      else
        break
      fi
    elif [[ "${cask_updated}" == 'e' ]]; then
      edit_cask "${cask_file}"
      if ! is_version_latest "${cask_file}"; then # Recheck sha256 values if version isn't :latest
        sha_change "${cask_file}"
      fi
      cask_updated='false'
      clear_warnings
    elif [[ "${cask_updated}" == 'n' ]]; then
      abort 'You decided to abort.'
    fi
  done

  # Skip if no changes were made, submit otherwise
  if git diff-index --quiet HEAD --; then
    skip 'No changes made to the cask. Skipping…'
    continue
  else
    echo 'Submitting…'
  fi

  # Grab version as it ended up in the cask
  cask_version="$(brew cask _stanza version "${cask_file}")"

  # Commit, push, submit pull request, clean
  [[ "${old_cask_version}" == "${cask_version}" ]] && commit_message="Update ${cask_name}" || commit_message="Update ${cask_name} from ${old_cask_version} to ${cask_version}"

  if [[ -n "${reword_commit}" ]]; then
    git commit "${cask_file}" --message "${commit_message}" --edit --quiet
    commit_message="$(git log --format=%B -n 1 HEAD | head -n 1)"
  else
    git commit "${cask_file}" --message "${commit_message}" --quiet
  fi

  pr_message="${commit_message}\n\nAfter making all changes to the cask:\n\n- [x] \`brew cask audit --download {{cask_file}}\` is error-free.\n- [x] \`brew cask style --fix {{cask_file}}\` left no offenses.\n- [x] The commit message includes the cask’s name and version."
  [[ -n "${issue_to_close}" ]] && pr_message+="\n\nCloses #${issue_to_close}."
  [[ -n "${extra_message}" ]] && pr_message+="\n\n${extra_message}"
  submit_pr_from="${github_username}:${cask_branch}"

  git push --force "${cask_repair_remote_name}" "${cask_branch}" --quiet 2> "${submission_error_log}"

  if [[ "${?}" -ne 0 ]]; then
    # Fix common push errors
    if grep --quiet 'shallow update not allowed' "${submission_error_log}"; then
      echo 'Push failed due to shallow repo. Unshallowing…'
      HOMEBREW_NO_AUTO_UPDATE=1 brew tap --full "homebrew/$(current_tap)"
      git push --force "${cask_repair_remote_name}" "${cask_branch}" --quiet 2> "${submission_error_log}"

      [[ "${?}" -ne 0 ]] && push_failure_message "$(< "${submission_error_log}")"
    else
      push_failure_message "$(< "${submission_error_log}")"
    fi
  fi

  pr_link=$(hub pull-request -b "${submit_pr_to}" -h "${submit_pr_from}" -m "$(echo -e "${pr_message}")")

  if [[ -n "${pr_link}" ]]; then
    if [[ -n "${install_now}" ]]; then
      success_message 'Updating cask locally…'
      brew cask reinstall "${cask_file}"
    else
      echo -e "\nYou can upgrade the cask right now from your personal branch:\n  brew cask reinstall https://raw.githubusercontent.com/${github_username}/$(current_tap)/${cask_branch}/Casks/${cask_name}.rb"
    fi

    clean
    success_message "\nSubmitted (${pr_link})\n"
  else
    abort 'There was an error submitting the pull request. Please open a bug report on the repo for this script (https://github.com/vitorgalvao/tiny-scripts).'
  fi
done
