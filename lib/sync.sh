#!/usr/bin/env bash
# sync.sh — Core sync logic: rebuild all/ index and tool directory symlinks

# ─── Build the all/ flat index ──────────────────────────────────────────

rebuild_all_index() {
    local all_dir="$SKILLS_ROOT/all"
    mkdir -p "$all_dir"

    # Clean existing symlinks in all/
    remove_symlinks_in "$all_dir"

    local count=0

    # Priority order: user > utility > vendor/*
    # User skills
    if [[ -d "$SKILLS_ROOT/user" ]]; then
        for skill in "$SKILLS_ROOT/user"/*/; do
            [[ -e "$skill" ]] || continue
            local name
            name=$(basename "$skill")
            [[ "$name" == .* ]] && continue
            make_link "../user/$name" "$all_dir/$name"
            ((count++))
        done
    fi

    # Utility skills
    if [[ -d "$SKILLS_ROOT/utility" ]]; then
        for skill in "$SKILLS_ROOT/utility"/*/; do
            [[ -e "$skill" ]] || continue
            local name
            name=$(basename "$skill")
            [[ "$name" == .* ]] && continue
            # Skip if user already has one with same name
            [[ -e "$all_dir/$name" ]] && continue
            make_link "../utility/$name" "$all_dir/$name"
            ((count++))
        done
    fi

    # Vendor skills (iterate vendor subdirectories)
    if [[ -d "$SKILLS_ROOT/vendor" ]]; then
        for vendor_dir in "$SKILLS_ROOT/vendor"/*/; do
            [[ -e "$vendor_dir" ]] || continue
            local vendor
            vendor=$(basename "$vendor_dir")
            [[ "$vendor" == .* ]] && continue
            for skill in "$vendor_dir"*/; do
                [[ -e "$skill" ]] || continue
                local name
                name=$(basename "$skill")
                [[ "$name" == .* ]] && continue
                # Skip if higher priority already claimed this name
                [[ -e "$all_dir/$name" ]] && continue
                make_link "../vendor/$vendor/$name" "$all_dir/$name"
                ((count++))
            done
        done
    fi

    log_ok "all/ index: $count skills"
}

# ─── Sync a single tool directory ───────────────────────────────────────

sync_tool_dir() {
    local skills_dir="$1"   # e.g., /Users/zkb/.claude/skills
    local link_prefix="$2"  # e.g., ../../.skills/all

    [[ -d "$skills_dir" ]] || mkdir -p "$skills_dir"

    # Remove old symlinks (preserve real dirs like .system)
    remove_symlinks_in "$skills_dir"

    # Create symlinks for each skill in all/
    local count=0
    for skill in "$SKILLS_ROOT/all"/*/; do
        [[ -e "$skill" ]] || continue
        local name
        name=$(basename "$skill")
        make_link "$link_prefix/$name" "$skills_dir/$name"
        ((count++))
    done

    log_ok "$(basename "$(dirname "$skills_dir")")/skills/: $count links"
}

# ─── Sync all tool directories ──────────────────────────────────────────

sync_all_tools() {
    log_info "Syncing dotfile tool directories..."

    for tool in "${DOTFILE_TOOLS[@]}"; do
        local skills_dir="$HOME/.$tool/skills"
        # Skip if the parent tool dir doesn't exist at all
        if [[ ! -d "$HOME/.$tool" ]]; then
            continue
        fi
        local prefix
        prefix=$(get_link_prefix "dotfile")
        sync_tool_dir "$skills_dir" "$prefix"
    done

    log_info "Syncing .config/ tool directories..."

    for tool in "${CONFIG_TOOLS[@]}"; do
        local skills_dir="$HOME/.config/$tool/skills"
        if [[ ! -d "$HOME/.config/$tool" ]]; then
            continue
        fi
        local prefix
        prefix=$(get_link_prefix "config")
        sync_tool_dir "$skills_dir" "$prefix"
    done
}

# ─── cmd_init ───────────────────────────────────────────────────────────

cmd_init() {
    log_info "Initializing $SKILLS_ROOT..."

    if [[ "$DRY_RUN" != "true" ]]; then
        mkdir -p "$SKILLS_ROOT"/{user,utility,vendor/codex,all,bin}
    else
        log_action "mkdir -p $SKILLS_ROOT/{user,utility,vendor/codex,all,bin}"
    fi

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        registry_init
    fi

    log_ok "Initialized $SKILLS_ROOT"
}

# ─── cmd_migrate ────────────────────────────────────────────────────────

cmd_migrate() {
    log_info "Starting migration..."

    # Ensure directory structure exists
    cmd_init

    # Step 1: Migrate user skills from ~/.claude/skills/
    log_info "Migrating user skills from ~/.claude/skills/..."
    local claude_skills="$HOME/.claude/skills"
    if [[ -d "$claude_skills" ]]; then
        for entry in "$claude_skills"/*/; do
            [[ -e "$entry" ]] || continue
            local name
            name=$(basename "$entry")
            [[ "$name" == .* ]] && continue
            # Skip symlinks (these point to .agents/skills/ etc.)
            [[ -L "${entry%/}" ]] && continue
            safe_move "${entry%/}" "$SKILLS_ROOT/user"
        done
    fi

    # Step 2: Migrate utility skills from ~/.agents/skills/
    log_info "Migrating utility skills from ~/.agents/skills/..."
    local agents_skills="$HOME/.agents/skills"
    if [[ -d "$agents_skills" ]]; then
        for entry in "$agents_skills"/*/; do
            [[ -e "$entry" ]] || continue
            local name
            name=$(basename "$entry")
            [[ "$name" == .* ]] && continue
            [[ -L "${entry%/}" ]] && continue
            safe_move "${entry%/}" "$SKILLS_ROOT/utility"
        done
    fi

    # Step 3: Migrate vendor skills from ~/.codex/skills/ (real dirs only)
    log_info "Migrating vendor skills from ~/.codex/skills/..."
    local codex_skills="$HOME/.codex/skills"
    if [[ -d "$codex_skills" ]]; then
        for entry in "$codex_skills"/*/; do
            [[ -e "$entry" ]] || continue
            local name
            name=$(basename "$entry")
            # Skip hidden dirs (.system, .DS_Store)
            [[ "$name" == .* ]] && continue
            # Skip symlinks (these point to .claude/skills/)
            [[ -L "${entry%/}" ]] && continue
            safe_move "${entry%/}" "$SKILLS_ROOT/vendor/codex"
        done
    fi

    # Step 4: Clean broken symlinks everywhere
    log_info "Cleaning broken symlinks..."
    local broken_count=0
    for dir in "$HOME/.codex/skills" "$HOME/.cursor/skills" "$HOME/.claude/skills" "$HOME/.agents/skills"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r link; do
                [[ -z "$link" ]] && continue
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_action "rm broken: $link"
                else
                    rm "$link"
                fi
                ((broken_count++))
            done < <(list_broken_links "$dir")
        fi
    done
    [[ $broken_count -gt 0 ]] && log_ok "Cleaned $broken_count broken symlinks"

    # Step 5: Also clean remaining symlinks in source dirs (old cross-references)
    log_info "Cleaning old symlinks from source directories..."
    for dir in "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.codex/skills"; do
        if [[ -d "$dir" ]]; then
            remove_symlinks_in "$dir"
        fi
    done

    # Step 6: Rebuild all/ index
    log_info "Building flat index..."
    rebuild_all_index

    # Step 7: Sync all tool directories
    log_info "Syncing all tool directories..."
    sync_all_tools

    # Step 8: Rebuild registry
    log_info "Rebuilding registry..."
    registry_rebuild

    log ""
    log "${GREEN}${BOLD}Migration complete!${RESET}"
    log "Run ${CYAN}skillctl status${RESET} to verify."
}

# ─── cmd_sync ───────────────────────────────────────────────────────────

cmd_sync() {
    rebuild_all_index
    sync_all_tools
    registry_rebuild
    [[ "$QUIET" != "true" ]] && log_ok "Sync complete"
}
