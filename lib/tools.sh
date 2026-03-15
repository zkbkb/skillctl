#!/usr/bin/env bash
# tools.sh — Per-tool configuration with fzf TUI (jq-powered, fast)
# Main: a/s/i/e = set mode, Enter = drill into skill picker / apply sync
# Skill picker: fzf --multi with Tab toggle, pre-selects based on current mode

# ─── Build tool list for main fzf ──────────────────────────────────────

_build_tools_fzf() {
    local i
    for ((i = 0; i < ${#TOOL_NAMES[@]}; i++)); do
        local tool="${TOOL_NAMES[$i]}"
        local skills_dir="${TOOL_SKILLS_DIRS[$i]}"
        local mode="${TOOL_SYNC_MODES[$i]:-all}"
        local tool_path="${TOOL_PATHS[$i]}"
        local display_dir="${skills_dir/$HOME/~}"

        local link_count=0
        if [[ -d "$skills_dir" ]]; then
            for entry in "$skills_dir"/*; do
                [[ -L "$entry" ]] && ((link_count++))
            done
        fi

        local installed=""
        [[ ! -d "$tool_path" ]] && installed=" (not installed)"

        local mode_icon=""
        case "$mode" in
            all)        mode_icon="● all" ;;
            selective)  mode_icon="◐ selective" ;;
            ignore)     mode_icon="○ ignore" ;;
            external)   mode_icon="◇ external" ;;
        esac

        printf "%s\t  %-20s  %-14s  %3d links  %s%s\n" \
            "$tool" "$tool" "$mode_icon" "$link_count" "$display_dir" "$installed"
    done
    printf "%s\t  %s\n" "__apply__" ">>> Apply & Sync"
}

# ─── Write temp scripts for fzf callbacks ───────────────────────────────

_tools_write_scripts() {
    # ── Preview (jq-powered) ──
    cat > "$_TOOLS_PREVIEW" << 'EOF'
#!/usr/bin/env bash
tool="$1"; cf="$2"
if [[ "$tool" == "__apply__" ]]; then
    echo "Apply all mode changes and sync skill"
    echo "symlinks to tool directories."
    exit 0
fi
jq -r --arg t "$tool" '
.tools[$t] // empty |
"Tool:       \($t)",
"Path:       \(.path)",
"Skills Dir: \(.skills_dir)",
"Mode:       \(.sync_mode // "all")",
"Type:       \(.type // "?")",
"Prefix:     \(.link_prefix // "?")",
"",
(if .sync_mode == "selective" and (.selected_skills | length) > 0
 then "Selected Skills (\(.selected_skills | length)):",
      (.selected_skills[] | "  ● \(.)"), ""
 else empty end),
(if (.protected_paths // [] | length) > 0
 then "Protected:  \(.protected_paths | join(":"))", ""
 else empty end),
(.detection // {} |
 if .tier then "Detection:  tier \(.tier), \(.confidence // "?")%",
                "Markers:    \(.markers // [] | join(" "))", ""
 else empty end)
' "$cf" 2>/dev/null
EOF
    chmod +x "$_TOOLS_PREVIEW"

    # ── Mode setter (jq) ──
    cat > "$_TOOLS_SETMODE" << MODEOF
#!/usr/bin/env bash
tool="\$1"; mode="\$2"; cf="$CONFIG_FILE"
[[ "\$tool" == "__apply__" ]] && exit 0
updated=\$(jq --arg t "\$tool" --arg m "\$mode" '.tools[\$t].sync_mode = \$m' "\$cf")
echo "\$updated" > "\$cf.tmp.\$\$" && mv "\$cf.tmp.\$\$" "\$cf"
MODEOF
    chmod +x "$_TOOLS_SETMODE"

    # ── Reload list ──
    cat > "$_TOOLS_RELOAD" << RELOADEOF
#!/usr/bin/env bash
export QUIET=true DRY_RUN=false SKILLS_ROOT="$SKILLS_ROOT" CONFIG_FILE="$CONFIG_FILE"
LIB_DIR="$LIB_DIR"
source "\$LIB_DIR/config.sh"
source "\$LIB_DIR/utils.sh"
load_config 2>/dev/null || true
for ((i = 0; i < \${#TOOL_NAMES[@]}; i++)); do
    tool="\${TOOL_NAMES[\$i]}"
    sd="\${TOOL_SKILLS_DIRS[\$i]}"
    mode="\${TOOL_SYNC_MODES[\$i]:-all}"
    tp="\${TOOL_PATHS[\$i]}"
    dd="\${sd/\$HOME/~}"
    lc=0
    if [[ -d "\$sd" ]]; then
        for e in "\$sd"/*; do [[ -L "\$e" ]] && ((lc++)); done
    fi
    inst=""
    [[ ! -d "\$tp" ]] && inst=" (not installed)"
    case "\$mode" in
        all) mi="● all" ;; selective) mi="◐ selective" ;;
        ignore) mi="○ ignore" ;; external) mi="◇ external" ;;
    esac
    printf "%s\t  %-20s  %-14s  %3d links  %s%s\n" "\$tool" "\$tool" "\$mi" "\$lc" "\$dd" "\$inst"
done
printf "%s\t  %s\n" "__apply__" ">>> Apply & Sync"
RELOADEOF
    chmod +x "$_TOOLS_RELOAD"

    # ── Enter handler: skill picker or sync ──
    cat > "$_TOOLS_ENTER" << 'ENTEREOF'
#!/usr/bin/env bash
tool="$1"; SR="$2"; CF="$3"; LD="$4"

if [[ "$tool" == "__apply__" ]]; then
    "$SR/bin/skillctl" sync 2>&1
    echo ""; echo "Press Enter to return..."
    read -r
    exit 0
fi

# ─── Skill picker sub-TUI ─────────────────────────────────────────
cur_mode=$(jq -r --arg t "$tool" '.tools[$t].sync_mode // "all"' "$CF" 2>/dev/null)

# Build all skills list
all_skills=""
for d in "$SR/all"/*/; do
    [[ -e "$d" ]] || continue
    s=$(basename "$d")
    [[ "$s" == .* ]] && continue
    all_skills+="$s"$'\n'
done
all_skills=$(echo "$all_skills" | sort)

if [[ -z "$all_skills" ]]; then
    echo "No skills in $SR/all/"
    read -r; exit 0
fi

total=$(echo "$all_skills" | wc -l | tr -d ' ')

# Build fzf args as an array
fzf_args=(
    --multi
    --header "Skills for: $tool ($cur_mode)  |  Tab=toggle  Enter=confirm  Esc=cancel"
    --preview "f=$SR/all/{}/SKILL.md; [ -f \"\$f\" ] && head -40 \"\$f\" || echo 'No SKILL.md'"
    --preview-window=right:45%:wrap
    --marker='● '
    --pointer='>'
    --border
    --prompt="skill> "
    --height=80%
    --layout=reverse
    --bind "tab:toggle+down"
    --bind "shift-tab:toggle+up"
)

# Pre-selection strategy (no --select flag needed)
if [[ "$cur_mode" == "all" ]]; then
    # All mode: start with everything toggled on
    fzf_args+=(--bind "start:toggle-all")
elif [[ "$cur_mode" == "selective" ]]; then
    # Selective: put selected skills first, then toggle that group
    cur_selected=$(jq -r --arg t "$tool" '.tools[$t].selected_skills // [] | .[]' "$CF" 2>/dev/null)
    if [[ -n "$cur_selected" ]]; then
        # Build input: selected first (marked), then unselected
        selected_set=" $(echo "$cur_selected" | tr '\n' ' ') "
        sorted_skills=""
        # Selected items first
        while IFS= read -r sk; do
            [[ -n "$sk" ]] && [[ "$selected_set" == *" $sk "* ]] && sorted_skills+="$sk"$'\n'
        done <<< "$all_skills"
        # Then unselected
        while IFS= read -r sk; do
            [[ -n "$sk" ]] && [[ "$selected_set" != *" $sk "* ]] && sorted_skills+="$sk"$'\n'
        done <<< "$all_skills"
        all_skills="$sorted_skills"
        # Count selected to know how many to toggle
        sel_count=$(echo "$cur_selected" | grep -c . || true)
        # Toggle first N items using repeated toggle+down
        toggle_chain="toggle+down"
        i=1
        while [[ $i -lt $sel_count ]]; do
            toggle_chain+="+toggle+down"
            ((i++))
        done
        fzf_args+=(--bind "start:$toggle_chain")
    fi
fi

chosen=$(echo "$all_skills" | fzf "${fzf_args[@]}") || exit 0

chosen_count=$(echo "$chosen" | wc -l | tr -d ' ')

if [[ "$chosen_count" -eq "$total" ]]; then
    updated=$(jq --arg t "$tool" '.tools[$t].sync_mode = "all" | .tools[$t].selected_skills = []' "$CF")
    echo "$updated" > "$CF.tmp.$$" && mv "$CF.tmp.$$" "$CF"
    echo ""; echo "$tool → all ($total skills)"
else
    skills_json=$(echo "$chosen" | jq -R . | jq -s .)
    updated=$(jq --arg t "$tool" --argjson s "$skills_json" \
        '.tools[$t].sync_mode = "selective" | .tools[$t].selected_skills = $s' "$CF")
    echo "$updated" > "$CF.tmp.$$" && mv "$CF.tmp.$$" "$CF"
    echo ""; echo "$tool → selective ($chosen_count/$total skills)"
fi
sleep 0.5
ENTEREOF
    chmod +x "$_TOOLS_ENTER"
}

# ─── FZF tools TUI ─────────────────────────────────────────────────────

_tools_fzf() {
    _TOOLS_PREVIEW=$(mktemp /tmp/skillctl-tp.XXXXXX)
    _TOOLS_SETMODE=$(mktemp /tmp/skillctl-tm.XXXXXX)
    _TOOLS_RELOAD=$(mktemp /tmp/skillctl-tr.XXXXXX)
    _TOOLS_ENTER=$(mktemp /tmp/skillctl-te.XXXXXX)
    _tools_write_scripts

    local header="a=all  s=selective  i=ignore  e=external  enter=configure skills  esc=exit"

    _build_tools_fzf | fzf \
        --ansi \
        --delimiter $'\t' \
        --with-nth '2..' \
        --header "$header" \
        --preview "bash $_TOOLS_PREVIEW {1} $CONFIG_FILE" \
        --preview-window=right:45%:wrap \
        --bind "a:execute-silent(bash $_TOOLS_SETMODE {1} all)+reload(bash $_TOOLS_RELOAD)" \
        --bind "s:execute-silent(bash $_TOOLS_SETMODE {1} selective)+reload(bash $_TOOLS_RELOAD)" \
        --bind "i:execute-silent(bash $_TOOLS_SETMODE {1} ignore)+reload(bash $_TOOLS_RELOAD)" \
        --bind "e:execute-silent(bash $_TOOLS_SETMODE {1} external)+reload(bash $_TOOLS_RELOAD)" \
        --bind "enter:execute(bash $_TOOLS_ENTER {1} $SKILLS_ROOT $CONFIG_FILE $LIB_DIR)+reload(bash $_TOOLS_RELOAD)" \
        --border \
        --prompt="tool> " \
        --height=80% \
        --layout=reverse \
        --track \
    || true

    rm -f "$_TOOLS_PREVIEW" "$_TOOLS_SETMODE" "$_TOOLS_RELOAD" "$_TOOLS_ENTER"
    load_config 2>/dev/null || true
}

# ─── cmd_tools entry point ──────────────────────────────────────────────

cmd_tools() {
    local subcmd="${1:-}"
    shift || true
    case "$subcmd" in
        set)      cmd_tools_set "$@" ;;
        select)   cmd_tools_select "$@" ;;
        list)     cmd_tools_list ;;
        *)
            if [[ "$HAS_FZF" == "true" && ${#TOOL_NAMES[@]} -gt 0 ]]; then
                _tools_fzf
            else
                cmd_tools_list
            fi
            ;;
    esac
}

# ─── Text fallback ─────────────────────────────────────────────────────

cmd_tools_list() {
    if [[ ${#TOOL_NAMES[@]} -eq 0 ]]; then
        log_warn "No tools configured. Run 'skillctl scan' first."
        return 1
    fi
    echo ""
    printf "${BOLD}%-20s %-14s %5s  %s${RESET}\n" "Tool" "Mode" "Links" "Skills Dir"
    printf "%s\n" "$(printf '─%.0s' {1..80})"
    local i
    for ((i = 0; i < ${#TOOL_NAMES[@]}; i++)); do
        local tool="${TOOL_NAMES[$i]}" skills_dir="${TOOL_SKILLS_DIRS[$i]}"
        local mode="${TOOL_SYNC_MODES[$i]:-all}" tool_path="${TOOL_PATHS[$i]}"
        local display_dir="${skills_dir/$HOME/~}"
        local link_count=0
        if [[ -d "$skills_dir" ]]; then
            for entry in "$skills_dir"/*; do [[ -L "$entry" ]] && ((link_count++)); done
        fi
        local md=""
        case "$mode" in
            all) md="${GREEN}● all${RESET}" ;; selective) md="${CYAN}◐ selective${RESET}" ;;
            ignore) md="${DIM}○ ignore${RESET}" ;; external) md="${YELLOW}◇ external${RESET}" ;;
        esac
        printf "%-20s %-22b %3d    %s" "$tool" "$md" "$link_count" "$display_dir"
        [[ ! -d "$tool_path" ]] && printf "  ${DIM}(not installed)${RESET}"
        echo ""
    done
    local total=${#TOOL_NAMES[@]} ac=0 sc=0 ic=0 ec=0
    for ((i = 0; i < total; i++)); do
        case "${TOOL_SYNC_MODES[$i]:-all}" in
            all) ((ac++)) ;; selective) ((sc++)) ;; ignore) ((ic++)) ;; external) ((ec++)) ;;
        esac
    done
    echo ""
    echo -e "Total: $total (${GREEN}$ac all${RESET}, ${CYAN}$sc selective${RESET}, ${DIM}$ic ignore${RESET}, ${YELLOW}$ec external${RESET})"
}

# ─── CLI subcommands ────────────────────────────────────────────────────

cmd_tools_set() {
    local tool="${1:-}" mode="${2:-}"
    [[ -z "$tool" || -z "$mode" ]] && { log_error "Usage: skillctl tools set <tool> <all|selective|ignore|external>"; return 1; }
    [[ ! -f "$CONFIG_FILE" ]] && { log_error "No config. Run 'skillctl scan'."; return 1; }
    case "$mode" in all|selective|ignore|external) ;; *) log_error "Invalid mode: $mode"; return 1 ;; esac
    bash "$LIB_DIR/config_writer.sh" "$CONFIG_FILE" set_tool_mode "$tool" "$mode"
    log_ok "Set $tool → $mode"
    load_config 2>/dev/null || true
}

cmd_tools_select() {
    local tool="${1:-}"; shift || true
    [[ -z "$tool" || $# -eq 0 ]] && { log_error "Usage: skillctl tools select <tool> <skill1> [skill2 ...]"; return 1; }
    [[ ! -f "$CONFIG_FILE" ]] && { log_error "No config. Run 'skillctl scan'."; return 1; }
    local valid=()
    for sk in "$@"; do
        [[ -e "$SKILLS_ROOT/all/$sk" ]] && valid+=("$sk") || log_warn "Not found: $sk"
    done
    [[ ${#valid[@]} -eq 0 ]] && { log_error "No valid skills."; return 1; }
    bash "$LIB_DIR/config_writer.sh" "$CONFIG_FILE" set_tool_skills "$tool" "${valid[@]}"
    log_ok "Set $tool → selective (${#valid[@]} skills)"
    load_config 2>/dev/null || true
}
