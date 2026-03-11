#!/usr/bin/env bash
# utils.sh — Shared utility functions

# Colors (disabled if not a terminal or QUIET)
if [[ -t 1 ]] && [[ "$QUIET" != "true" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' RESET=''
fi

log() {
    [[ "$QUIET" == "true" ]] && return
    echo -e "$@"
}

log_info() {
    log "${BLUE}info${RESET}  $*"
}

log_ok() {
    log "${GREEN}ok${RESET}    $*"
}

log_warn() {
    echo -e "${YELLOW}warn${RESET}  $*" >&2
}

log_error() {
    echo -e "${RED}error${RESET} $*" >&2
}

log_action() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "${DIM}(dry-run)${RESET} $*"
    else
        log "${CYAN}>>>${RESET}   $*"
    fi
}

# Count items in a directory (non-hidden, non-DS_Store)
count_skills_in() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo 0
        return
    fi
    local count=0
    for entry in "$dir"/*/; do
        [[ -e "$entry" ]] || continue
        local name
        name=$(basename "$entry")
        [[ "$name" == ".DS_Store" || "$name" == ".system" ]] && continue
        ((count++))
    done
    echo "$count"
}

# Count broken symlinks in a directory
count_broken_links() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo 0
        return
    fi
    local count=0
    for link in "$dir"/*; do
        [[ -L "$link" ]] && [[ ! -e "$link" ]] && ((count++))
    done
    echo "$count"
}

# List broken symlinks in a directory
list_broken_links() {
    local dir="$1"
    [[ ! -d "$dir" ]] && return
    for link in "$dir"/*; do
        if [[ -L "$link" ]] && [[ ! -e "$link" ]]; then
            echo "$link"
        fi
    done
}

# Safe move: move directory, skip if destination exists
safe_move() {
    local src="$1" dst="$2"
    local name
    name=$(basename "$src")
    if [[ -d "$dst/$name" ]]; then
        log_warn "Skip: $dst/$name already exists"
        return 1
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log_action "mv $src → $dst/$name"
    else
        mv "$src" "$dst/"
        log_action "Moved: $name"
    fi
}

# Remove only symlinks from a directory (preserve real dirs and files)
remove_symlinks_in() {
    local dir="$1"
    [[ ! -d "$dir" ]] && return
    for entry in "$dir"/*; do
        [[ -L "$entry" ]] || continue
        if [[ "$DRY_RUN" == "true" ]]; then
            log_action "rm symlink: $(basename "$entry")"
        else
            rm "$entry"
        fi
    done
}

# Create a relative symlink
make_link() {
    local target="$1" link_path="$2"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_action "ln -s $target $link_path"
    else
        ln -s "$target" "$link_path"
    fi
}
