#!/usr/bin/env bash
# manage.sh — Skill management commands: status, list, add, remove, doctor

# ─── cmd_status ─────────────────────────────────────────────────────────

cmd_status() {
    echo -e "${BOLD}skillctl status${RESET}"
    echo ""

    # Count skills by category
    local user_count vendor_count utility_count total_count
    user_count=$(count_skills_in "$SKILLS_ROOT/user")
    utility_count=$(count_skills_in "$SKILLS_ROOT/utility")
    vendor_count=0
    if [[ -d "$SKILLS_ROOT/vendor" ]]; then
        for vd in "$SKILLS_ROOT/vendor"/*/; do
            [[ -e "$vd" ]] || continue
            local vc
            vc=$(count_skills_in "$vd")
            vendor_count=$((vendor_count + vc))
        done
    fi
    total_count=$((user_count + utility_count + vendor_count))

    local all_count
    all_count=$(count_skills_in "$SKILLS_ROOT/all")

    echo -e "${BOLD}Canonical directory:${RESET} $SKILLS_ROOT"
    echo -e "${BOLD}Skills:${RESET}"
    echo "  user:     $user_count"
    echo "  utility:  $utility_count"
    echo "  vendor:   $vendor_count"
    echo "  total:    $total_count"
    echo "  all/:     $all_count (flat index)"
    echo ""

    # Check broken links in all/
    local all_broken
    all_broken=$(count_broken_links "$SKILLS_ROOT/all")
    if [[ $all_broken -gt 0 ]]; then
        echo -e "${RED}Broken links in all/:${RESET} $all_broken"
        list_broken_links "$SKILLS_ROOT/all" | while read -r link; do
            echo "  - $(basename "$link")"
        done
    else
        echo -e "${GREEN}No broken links in all/${RESET}"
    fi
    echo ""

    # Check each tool directory
    echo -e "${BOLD}Tool directories:${RESET}"
    local tool_ok=0 tool_drift=0 tool_skip=0
    for tool in "${TOOL_NAMES[@]}"; do
        _tool_index "$tool" || continue
        local skills_dir="${TOOL_SKILLS_DIRS[$_IDX]}"
        local tool_path="${TOOL_PATHS[$_IDX]}"
        local mode="${TOOL_SYNC_MODES[$_IDX]:-all}"
        local display_dir="${skills_dir/$HOME/~}"

        [[ -d "$tool_path" ]] || continue

        # Mode label
        local mode_label=""
        case "$mode" in
            all)        mode_label="${GREEN}[all]${RESET}" ;;
            selective)  mode_label="${CYAN}[sel]${RESET}" ;;
            ignore)     mode_label="${DIM}[ign]${RESET}" ;;
            external)   mode_label="${YELLOW}[ext]${RESET}" ;;
        esac

        if [[ "$mode" == "ignore" || "$mode" == "external" ]]; then
            ((tool_skip++))
            continue
        fi

        if [[ ! -d "$skills_dir" ]]; then
            echo -e "  $mode_label ${YELLOW}$display_dir${RESET}  missing"
            ((tool_drift++))
            continue
        fi

        local link_count=0 broken=0
        for entry in "$skills_dir"/*; do
            [[ -e "$entry" || -L "$entry" ]] || continue
            local ename
            ename=$(basename "$entry")
            [[ "$ename" == .* ]] && continue
            if [[ -L "$entry" ]]; then
                ((link_count++))
                [[ ! -e "$entry" ]] && ((broken++))
            fi
        done

        if [[ $broken -gt 0 ]]; then
            echo -e "  $mode_label ${RED}$tool${RESET}  $link_count links, $broken broken"
            ((tool_drift++))
        elif [[ "$mode" == "all" && $link_count -ne $all_count ]]; then
            echo -e "  $mode_label ${YELLOW}$tool${RESET}  $link_count links (expected $all_count)"
            ((tool_drift++))
        else
            ((tool_ok++))
        fi
    done

    echo ""
    echo -e "  ${GREEN}$tool_ok synced${RESET}, ${YELLOW}$tool_drift drifted${RESET}, ${DIM}$tool_skip skipped${RESET}"

    # Registry info
    echo ""
    if [[ -f "$REGISTRY_FILE" ]]; then
        echo -e "${BOLD}Registry:${RESET}"
        registry_summary
    else
        echo -e "${YELLOW}No registry file. Run 'skillctl sync' to create.${RESET}"
    fi
}

# ─── cmd_list ───────────────────────────────────────────────────────────

cmd_list() {
    local filter="${1:-}"

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        log_warn "No registry. Run 'skillctl sync' first."
        # Fallback: list from filesystem
        echo -e "${BOLD}Skills (from filesystem):${RESET}"
        for cat_dir in "$SKILLS_ROOT/user" "$SKILLS_ROOT/utility"; do
            [[ -d "$cat_dir" ]] || continue
            local cat
            cat=$(basename "$cat_dir")
            for skill in "$cat_dir"/*/; do
                [[ -e "$skill" ]] || continue
                local name
                name=$(basename "$skill")
                [[ "$name" == .* ]] && continue
                printf "  %-8s  %s\n" "$cat" "$name"
            done
        done
        if [[ -d "$SKILLS_ROOT/vendor" ]]; then
            for vd in "$SKILLS_ROOT/vendor"/*/; do
                [[ -e "$vd" ]] || continue
                local vendor
                vendor=$(basename "$vd")
                for skill in "$vd"*/; do
                    [[ -e "$skill" ]] || continue
                    local name
                    name=$(basename "$skill")
                    [[ "$name" == .* ]] && continue
                    printf "  %-8s  %s\n" "vendor/$vendor" "$name"
                done
            done
        fi
        return
    fi

    if command -v jq &>/dev/null; then
        printf "%-40s %-16s %8s\n" "Name" "Category" "SKILL.md"
        printf "%s\n" "$(printf '─%.0s' {1..66})"
        local filt_lower
        filt_lower=$(echo "$filter" | tr '[:upper:]' '[:lower:]')
        jq -r --arg f "$filt_lower" '.skills | to_entries | sort_by(.key)[] |
            select(if $f != "" then (.key | ascii_downcase | contains($f)) or (.value.category | ascii_downcase | contains($f)) else true end) |
            "\(.key)\t\(.value.category)\t\(if .value.has_skill_md then "yes" else "no" end)"
        ' "$REGISTRY_FILE" 2>/dev/null | while IFS=$'\t' read -r name cat has_md; do
            printf "%-40s %-16s %8s\n" "$name" "$cat" "$has_md"
        done
        local total
        total=$(jq '.skills | length' "$REGISTRY_FILE" 2>/dev/null)
        echo ""
        echo "Total: $total skills"
    else
        python3 -c "
import json
with open('$REGISTRY_FILE') as f:
    data = json.load(f)
skills = data.get('skills', {})
filt = '$filter'.lower()
print(f\"{'Name':<40} {'Category':<16} {'SKILL.md':>8}\")
print('-' * 66)
for name in sorted(skills):
    info = skills[name]
    cat = info.get('category', '?')
    has_md = 'yes' if info.get('has_skill_md') else 'no'
    if filt and filt not in name.lower() and filt not in cat.lower():
        continue
    print(f'{name:<40} {cat:<16} {has_md:>8}')
print(f'\nTotal: {len(skills)} skills')
"
    fi
}

# ─── cmd_add ────────────────────────────────────────────────────────────

cmd_add() {
    local src="${1:-}"
    local category="${2:-user}"

    if [[ -z "$src" ]]; then
        log_error "Usage: skillctl add <skill-path> [user|utility]"
        return 1
    fi

    if [[ ! -d "$src" ]]; then
        log_error "Not a directory: $src"
        return 1
    fi

    local name
    name=$(basename "$src")
    local dest="$SKILLS_ROOT/$category/$name"

    if [[ -d "$dest" ]]; then
        log_error "Skill already exists: $dest"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_action "cp -R $src → $dest"
        log_action "Would run sync after add"
    else
        cp -R "$src" "$dest"
        log_ok "Added: $name ($category)"
        cmd_sync
    fi
}

# ─── cmd_remove ─────────────────────────────────────────────────────────

cmd_remove() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        log_error "Usage: skillctl remove <skill-name>"
        return 1
    fi

    local found=false
    for cat_dir in "$SKILLS_ROOT/user" "$SKILLS_ROOT/utility"; do
        if [[ -d "$cat_dir/$name" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_action "rm -rf $cat_dir/$name"
            else
                rm -rf "$cat_dir/$name"
                log_ok "Removed: $name from $(basename "$cat_dir")"
            fi
            found=true
            break
        fi
    done

    # Also check vendor dirs
    if [[ "$found" == "false" && -d "$SKILLS_ROOT/vendor" ]]; then
        for vd in "$SKILLS_ROOT/vendor"/*/; do
            [[ -e "$vd" ]] || continue
            if [[ -d "$vd$name" ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_action "rm -rf $vd$name"
                else
                    rm -rf "$vd$name"
                    log_ok "Removed: $name from vendor/$(basename "$vd")"
                fi
                found=true
                break
            fi
        done
    fi

    if [[ "$found" == "false" ]]; then
        log_error "Skill not found: $name"
        return 1
    fi

    cmd_sync
}

# ─── cmd_doctor ─────────────────────────────────────────────────────────

cmd_doctor() {
    log_info "Running diagnostics..."
    local issues=0

    # 1. Check for broken links in all/
    local all_broken
    all_broken=$(count_broken_links "$SKILLS_ROOT/all")
    if [[ $all_broken -gt 0 ]]; then
        log_warn "Found $all_broken broken links in all/"
        list_broken_links "$SKILLS_ROOT/all" | while read -r link; do
            log_warn "  Broken: $(basename "$link") → $(readlink "$link")"
            if [[ "$DRY_RUN" != "true" ]]; then
                rm "$link"
                log_action "Removed broken link: $(basename "$link")"
            fi
        done
        ((issues += all_broken))
    fi

    # 2. Check for broken links in tool directories
    for tool in "${TOOL_NAMES[@]}"; do
        _tool_index "$tool" || continue
        local mode="${TOOL_SYNC_MODES[$_IDX]:-all}"
        [[ "$mode" == "ignore" || "$mode" == "external" ]] && continue
        local skills_dir="${TOOL_SKILLS_DIRS[$_IDX]}"
        [[ -d "$skills_dir" ]] || continue
        local broken
        broken=$(count_broken_links "$skills_dir")
        if [[ $broken -gt 0 ]]; then
            log_warn "$tool/skills/: $broken broken links"
            list_broken_links "$skills_dir" | while read -r link; do
                if [[ "$DRY_RUN" != "true" ]]; then
                    rm "$link"
                fi
            done
            ((issues += broken))
        fi
    done

    # 3. Check for skills without SKILL.md
    log_info "Checking skill completeness..."
    for cat_dir in "$SKILLS_ROOT/user" "$SKILLS_ROOT/utility"; do
        [[ -d "$cat_dir" ]] || continue
        for skill in "$cat_dir"/*/; do
            [[ -e "$skill" ]] || continue
            local name
            name=$(basename "$skill")
            [[ "$name" == .* ]] && continue
            if [[ ! -f "$skill/SKILL.md" ]]; then
                log_warn "Missing SKILL.md: $(basename "$cat_dir")/$name"
                ((issues++))
            fi
        done
    done

    # 4. Check for skill name issues (spaces, mixed case)
    log_info "Checking naming conventions..."
    for cat_dir in "$SKILLS_ROOT/user" "$SKILLS_ROOT/utility"; do
        [[ -d "$cat_dir" ]] || continue
        for skill in "$cat_dir"/*/; do
            [[ -e "$skill" ]] || continue
            local name
            name=$(basename "$skill")
            [[ "$name" == .* ]] && continue
            if [[ "$name" == *" "* ]]; then
                log_warn "Name contains spaces: $name (in $(basename "$cat_dir")/)"
                ((issues++))
            fi
        done
    done

    echo ""
    if [[ $issues -eq 0 ]]; then
        log_ok "No issues found!"
    else
        log_warn "Found $issues issue(s)"
        if [[ "$DRY_RUN" != "true" ]]; then
            log_info "Broken links cleaned. Run 'skillctl sync' to re-establish links."
        fi
    fi
}
