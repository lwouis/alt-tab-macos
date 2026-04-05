#!/usr/bin/env bash
# Shared helpers for vendor/scripts/update_*.sh
# Source from each update script: . "$(dirname "$0")/lib/common.sh"
#
# Each update script follows the same shape:
#   require_update_flag "$@" "$0" "<desc>"   # arg check + usage line
#   mktempdir                                # sets $TMP, registers cleanup trap
#   git_clone_tag <url> <tag> "$TMP/src"     # or git_clone_commit
#   fetch_extract <url> "$TMP"               # for prebuilt archives
#   ... per-dep copying / pruning ...
#   write_upstream "$DEST" <version> <url>
#   done_msg "$DEST" <version>

# require_update_flag <user-args...> -- <script_path> <description>
# Bash can't easily take "$@" then trailing args, so the calling convention is:
#   require_update_flag "${1:-}" "$0" "refreshes vendor/Sparkle to 2.9.1"
require_update_flag() {
    local arg="$1" script="$2" desc="$3"
    if [[ "$arg" != "--update" ]]; then
        echo "usage: $script --update   ($desc)"
        exit 0
    fi
}

# mktempdir: creates a temp dir, exports $TMP, registers a cleanup trap.
# Trap is process-wide so this is safe to call from a function.
mktempdir() {
    TMP="$(mktemp -d)"
    trap "rm -rf '$TMP'" EXIT
}

# git_clone_tag <url> <tag> <dest>
# Shallow clone of a single tag (or branch). Fast and small. Progress goes to stderr so
# callers can $(capture) the function without polluting their variable.
git_clone_tag() {
    local url="$1" tag="$2" dest="$3"
    echo "→ cloning $url @ $tag" >&2
    git clone --depth=1 --branch "$tag" "$url" "$dest" >&2
}

# git_clone_commit <url> <commit> <dest>
# Full clone + checkout at a specific commit. Echoes the resolved SHA on stdout; progress
# goes to stderr so $(git_clone_commit …) captures just the SHA.
git_clone_commit() {
    local url="$1" commit="$2" dest="$3"
    echo "→ cloning $url and checking out ${commit:0:8}" >&2
    git clone "$url" "$dest" >&2
    git -C "$dest" checkout --quiet "$commit" >&2
    git -C "$dest" rev-parse HEAD
}

# fetch_extract <archive_url> <dest_dir>
# Downloads an archive and extracts it into <dest_dir>. Detects .tar.xz / .tar.gz / .zip
# by URL suffix. Leaves the archive in $dest_dir for inspection.
fetch_extract() {
    local url="$1" dest="$2"
    mkdir -p "$dest"
    local fname="${url##*/}"
    local archive="$dest/$fname"
    echo "→ downloading $fname"
    curl -fsSL "$url" -o "$archive"
    case "$fname" in
        *.tar.xz|*.tar.gz|*.tgz|*.tar) tar -xf "$archive" -C "$dest" ;;
        *.zip)                          unzip -q "$archive" -d "$dest" ;;
        *) echo "ERROR: unknown archive type: $fname" >&2; return 1 ;;
    esac
}

# keep_lprojs: returns (newline-separated) the lproj base names our app supports.
# Source of truth: resources/l10n/*.lproj. Also emits alternative spellings each
# vendored dep uses (Sparkle underscores, ShortcutRecorder BCP-47 Hans/Hant) so adding
# a language to the app only requires editing resources/l10n/.
keep_lprojs() {
    local lp name
    for lp in resources/l10n/*.lproj; do
        [ -d "$lp" ] || continue
        name="$(basename "$lp" .lproj)"
        printf '%s\n' "$name"
        case "$name" in
            pt-BR) printf 'pt_BR\n' ;;
            zh-CN) printf 'zh_CN\nzh-Hans\n' ;;
            zh-TW) printf 'zh_TW\nzh-Hant\n' ;;
            zh-HK) printf 'zh_HK\n' ;;
        esac
    done
}

# copy_kept_lprojs <src_dir> <dst_dir>
# Copies only the *.lproj subdirs whose name matches keep_lprojs.
copy_kept_lprojs() {
    local src="$1" dst="$2"
    [ -d "$src" ] || return 0
    mkdir -p "$dst"
    local kept; kept="$(keep_lprojs)"
    local lp name
    for lp in "$src"/*.lproj; do
        [ -e "$lp" ] || continue
        name="$(basename "$lp" .lproj)"
        if grep -Fxq -- "$name" <<< "$kept"; then
            cp -R "$lp" "$dst/"
        fi
    done
}

# rebuild_dest <dest_dir> <subdirs...>
# Wipes $dest_dir and re-creates it with the given subdirs.
rebuild_dest() {
    local dest="$1"; shift
    rm -rf "$dest"
    mkdir -p "$dest"
    for sub in "$@"; do mkdir -p "$dest/$sub"; done
}

# write_upstream <dest_dir> <version> <source_url>
write_upstream() {
    local dest="$1" version="$2" url="$3"
    cat > "$dest/UPSTREAM" <<EOF
VERSION=$version
SOURCE=$url
DATE=$(date -u +%Y-%m-%d)
EOF
}

# done_msg <dest_dir> <version>
done_msg() {
    local dest="$1" version="$2"
    echo
    echo "✓ Updated $dest to $version."
    echo "  Review the diff, then: git add $dest && git commit"
}

# apply_local_patches <dest_dir>
# If <dest>/patches/*.diff exists, apply them with `patch -p1` from inside <dest>.
apply_local_patches() {
    local dest="$1"
    [ -d "$dest/patches" ] || return 0
    local p
    for p in "$dest/patches"/*.diff; do
        [ -e "$p" ] || continue
        echo "→ applying $(basename "$p")"
        patch -p1 -d "$dest" < "$p"
    done
}
