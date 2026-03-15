#!/usr/bin/env bash
# tui.sh — Interactive TUI for skill management (fzf-based with fallback)

HAS_FZF=false
command -v fzf &>/dev/null && HAS_FZF=true

# ─── Helpers ────────────────────────────────────────────────────────────

# Build a skill list with metadata for display
_build_skill_table() {
    local filter="${1:-}"
    for cat_dir in "$SKILLS_ROOT/user" "$SKILLS_ROOT/utility"; do
        [[ -d "$cat_dir" ]] || continue
        local category_name="${cat_dir##*/}"
        for skill in "$cat_dir"/*/; do
            [[ -e "$skill" ]] || continue
            local sname="${skill%/}"
            sname="${sname##*/}"
            [[ "$sname" == .* ]] && continue
            local desc=""
            if [[ -f "$skill/SKILL.md" ]]; then
                desc=$(grep -m1 '^description:' "$skill/SKILL.md" 2>/dev/null | sed 's/^description: *//' | head -c 80)
            fi
            if [[ -z "$filter" ]] || [[ "$sname" == *"$filter"* ]] || [[ "$category_name" == *"$filter"* ]]; then
                printf "%-40s %-14s %s\n" "$sname" "[$category_name]" "$desc"
            fi
        done
    done
    if [[ -d "$SKILLS_ROOT/vendor" ]]; then
        for vd in "$SKILLS_ROOT/vendor"/*/; do
            [[ -e "$vd" ]] || continue
            local vendor="${vd%/}"
            vendor="${vendor##*/}"
            for skill in "$vd"*/; do
                [[ -e "$skill" ]] || continue
                local sname="${skill%/}"
                sname="${sname##*/}"
                [[ "$sname" == .* ]] && continue
                local desc=""
                if [[ -f "$skill/SKILL.md" ]]; then
                    desc=$(grep -m1 '^description:' "$skill/SKILL.md" 2>/dev/null | sed 's/^description: *//' | head -c 80)
                fi
                if [[ -z "$filter" ]] || [[ "$sname" == *"$filter"* ]] || [[ "vendor" == *"$filter"* ]]; then
                    printf "%-40s %-14s %s\n" "$sname" "[vendor/$vendor]" "$desc"
                fi
            done
        done
    fi
}

# Get the category dir for a skill by name
_find_skill_dir() {
    local name="$1"
    for cat_dir in "$SKILLS_ROOT/user" "$SKILLS_ROOT/utility"; do
        [[ -d "$cat_dir/$name" ]] && echo "$cat_dir/$name" && return
    done
    if [[ -d "$SKILLS_ROOT/vendor" ]]; then
        for vd in "$SKILLS_ROOT/vendor"/*/; do
            [[ -d "$vd$name" ]] && echo "$vd$name" && return
        done
    fi
}

# Get category label for a skill
_skill_category() {
    local path="$1"
    if [[ "$path" == *"/user/"* ]]; then echo "user"
    elif [[ "$path" == *"/utility/"* ]]; then echo "utility"
    elif [[ "$path" == *"/vendor/"* ]]; then
        # Extract vendor name from path like .../vendor/codex/skillname
        local stripped="${path%/*}"     # remove skill name
        local vname="${stripped##*/}"   # get vendor dir name
        echo "vendor/$vname"
    fi
}

# Count linked tools for a given skill name
_count_tool_links() {
    local name="$1"
    local count=0
    for tool in "${TOOL_NAMES[@]}"; do
        _tool_index "$tool" || continue
        local skills_dir="${TOOL_SKILLS_DIRS[$_IDX]}"
        [[ -L "$skills_dir/$name" ]] && ((count++))
    done
    echo "$count"
}

# ─── FZF-based interactive browser ─────────────────────────────────────

_fzf_browse() {
    local header="skillctl manage | ENTER=inspect  CTRL-D=delete  CTRL-E=edit  CTRL-R=refresh  ESC=quit"

    while true; do
        local selection
        selection=$(_build_skill_table | fzf \
            --ansi \
            --header "$header" \
            --preview 'name=$(echo {} | awk "{print \$1}"); dir=$(find '"$SKILLS_ROOT"'/{user,utility,vendor/*} -maxdepth 1 -name "$name" -type d 2>/dev/null | head -1); if [ -f "$dir/SKILL.md" ]; then head -60 "$dir/SKILL.md"; else echo "No SKILL.md found"; ls -la "$dir/" 2>/dev/null; fi' \
            --preview-window=right:50%:wrap \
            --expect=ctrl-d,ctrl-e,ctrl-r \
            --border \
            --prompt="skill> " \
            --height=80% \
            --layout=reverse \
        ) || break

        # Parse fzf output: first line is the key pressed, second is the selection
        local key
        key=$(echo "$selection" | head -1)
        local line
        line=$(echo "$selection" | tail -1)
        local skill_name
        skill_name=$(echo "$line" | awk '{print $1}')

        [[ -z "$skill_name" ]] && continue

        case "$key" in
            ctrl-d)
                _action_delete "$skill_name"
                ;;
            ctrl-e)
                _action_edit "$skill_name"
                ;;
            ctrl-r)
                # Refresh — just loop again
                continue
                ;;
            *)
                _action_inspect "$skill_name"
                ;;
        esac
    done
}

# ─── Actions ────────────────────────────────────────────────────────────

_action_inspect() {
    local name="$1"
    local dir
    dir=$(_find_skill_dir "$name")

    if [[ -z "$dir" ]]; then
        echo -e "${RED}Skill not found: $name${RESET}"
        return
    fi

    local category
    category=$(_skill_category "$dir")
    local links
    links=$(_count_tool_links "$name")

    echo ""
    echo -e "${BOLD}━━━ $name ━━━${RESET}"
    echo -e "  Category:   ${CYAN}$category${RESET}"
    echo -e "  Path:       $dir"
    echo -e "  Linked to:  ${GREEN}$links${RESET} tool directories"
    echo ""

    # Show directory contents
    echo -e "${DIM}Contents:${RESET}"
    ls -la "$dir/" | tail -n +2
    echo ""

    # Show SKILL.md frontmatter
    if [[ -f "$dir/SKILL.md" ]]; then
        echo -e "${DIM}SKILL.md frontmatter:${RESET}"
        sed -n '/^---$/,/^---$/p' "$dir/SKILL.md" 2>/dev/null
        echo ""
    fi

    if [[ "$HAS_FZF" != "true" ]]; then
        echo -e "Press ${BOLD}Enter${RESET} to continue..."
        read -r
    fi
}

_action_delete() {
    local name="$1"
    local dir
    dir=$(_find_skill_dir "$name")

    if [[ -z "$dir" ]]; then
        echo -e "${RED}Skill not found: $name${RESET}"
        return
    fi

    echo ""
    echo -e "${YELLOW}Delete skill: ${BOLD}$name${RESET}${YELLOW} from $(_skill_category "$dir")?${RESET}"
    echo -e "  Path: $dir"
    echo -n "  Type 'yes' to confirm: "
    read -r confirm
    if [[ "$confirm" == "yes" ]]; then
        rm -rf "$dir"
        # Remove from all/ index
        [[ -L "$SKILLS_ROOT/all/$name" ]] && rm "$SKILLS_ROOT/all/$name"
        # Remove from tool directories
        for tool in "${TOOL_NAMES[@]}"; do
            _tool_index "$tool" || continue
            local td="${TOOL_SKILLS_DIRS[$_IDX]}"
            [[ -L "$td/$name" ]] && rm "$td/$name"
        done
        echo -e "${GREEN}Deleted: $name${RESET}"
        # Rebuild registry
        registry_rebuild 2>/dev/null
    else
        echo "Cancelled."
    fi
}

_action_edit() {
    local name="$1"
    local dir
    dir=$(_find_skill_dir "$name")

    if [[ -z "$dir" ]]; then
        echo -e "${RED}Skill not found: $name${RESET}"
        return
    fi

    local editor="${EDITOR:-vim}"
    if [[ -f "$dir/SKILL.md" ]]; then
        "$editor" "$dir/SKILL.md"
    else
        echo -e "${YELLOW}No SKILL.md found. Opening directory...${RESET}"
        "$editor" "$dir"
    fi
}

# ─── Fallback: pure bash menu ──────────────────────────────────────────

_main_menu() {
    while true; do
        echo ""
        echo -e "${BOLD}skillctl v${VERSION:-0.2.0}${RESET}"
        local skill_count
        skill_count=$(count_skills_in "$SKILLS_ROOT/all")
        local tool_count=${#TOOL_NAMES[@]}
        echo -e "  ${DIM}$skill_count skills, $tool_count tools${RESET}"
        echo ""
        echo -e "  ${BOLD}Skills${RESET}"
        echo "    1) Browse / search skills"
        echo "    2) Inspect a skill"
        echo "    3) Add a skill"
        echo "    4) Remove a skill"
        echo ""
        echo -e "  ${BOLD}Tools${RESET}"
        echo "    5) List tools & sync modes"
        echo "    6) Configure tool sync mode"
        echo "    7) Scan for AI tools"
        echo ""
        echo -e "  ${BOLD}System${RESET}"
        echo "    8) Sync (apply changes)"
        echo "    9) Status & health check"
        echo "    0) Doctor (fix issues)"
        echo ""
        echo "    q) Quit"
        echo ""
        echo -n "  > "
        read -r choice

        case "$choice" in
            1)
                if [[ "$HAS_FZF" == "true" ]]; then
                    _fzf_browse
                else
                    echo -n "  Search (empty = all): "
                    read -r term
                    echo ""
                    _build_skill_table "$term"
                fi
                ;;
            2)
                echo -n "  Skill name: "
                read -r name
                _action_inspect "$name"
                ;;
            3)
                echo -n "  Path to skill directory: "
                read -r spath
                [[ -n "$spath" ]] && cmd_add "$spath"
                ;;
            4)
                echo -n "  Skill name to remove: "
                read -r name
                [[ -n "$name" ]] && cmd_remove "$name"
                ;;
            5)
                cmd_tools list
                ;;
            6)
                echo -n "  Tool name: "
                read -r tname
                [[ -z "$tname" ]] && continue
                echo -n "  Mode (all/selective/ignore/external): "
                read -r tmode
                [[ -n "$tmode" ]] && cmd_tools set "$tname" "$tmode"
                ;;
            7)
                cmd_scan
                ;;
            8)
                cmd_sync
                ;;
            9)
                cmd_status
                ;;
            0)
                cmd_doctor
                ;;
            q|Q|quit|exit)
                break
                ;;
            *)
                echo "  Unknown option: $choice"
                ;;
        esac
    done
}

# ─── Entry points ───────────────────────────────────────────────────────

# Default entry: fzf TUI if available, otherwise fall back to menu
cmd_manage() {
    if [[ "$HAS_FZF" == "true" ]]; then
        _fzf_browse
    else
        _main_menu
    fi
}

# Direct fzf skill browser (for quick access)
cmd_browse() {
    if [[ "$HAS_FZF" == "true" ]]; then
        _fzf_browse
    else
        echo -n "  Search (empty = all): "
        read -r term
        _build_skill_table "$term"
    fi
}
