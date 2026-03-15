#!/usr/bin/env bash
# discover.sh — AI tool auto-discovery engine

# Default exclude list (used when no config exists yet)
_DEFAULT_SCAN_EXCLUDE=(
    .Trash .cache .local .ssh .npm .docker .rbenv .pyenv .nvm .gradle
    .conda .gem .pub-cache .swiftpm .dart .dart-tool .bundle .mono
    .cups .thumbnails .matplotlib .ipython .jupyter .cocoapods
    .android .minikube .vs-kubernetes .vnc .arduinoIDE .dbclient
    .zsh_sessions .zsh_history .bash_history .lesshst .wget-hsts
    .DS_Store .CFUserTextEncoding .Xauthority .hushlogin
    .config .skills .skills-backup
)

# Known AI tool names — get a bonus score during scanning
_KNOWN_AI_TOOLS=(
    claude cursor codex gemini qwen cline copilot
    agents roo kiro junie trae trae-cn continue kilocode
    kode vibe zencoder adal commandcode factory iflow
    mcpjam moltbot mux neovate pochi qoder windsurf
    marscode cagent codeium codeverse augment aider
    opencode goose crush antigravity
)

_is_known_ai_tool() {
    local name="$1"
    for known in "${_KNOWN_AI_TOOLS[@]}"; do
        [[ "$name" == "$known" ]] && return 0
    done
    return 1
}

# ─── Scoring engine ─────────────────────────────────────────────────────

# Score a directory for AI tool likelihood.
# Sets: _SCORE, _TIER, _MARKERS (space-separated)
_score_directory() {
    local dir="$1"
    local tool_name="${2:-}"
    _SCORE=0
    _TIER=4
    _MARKERS=""

    # Tier 0: Known AI tool name bonus
    if [[ -n "$tool_name" ]] && _is_known_ai_tool "$tool_name"; then
        ((_SCORE += 20)); _MARKERS="$_MARKERS known-ai-tool"
    fi

    # Tier 1: Tool-specific metadata files (100% reliable)
    if [[ -f "$dir/.superclaude-metadata.json" ]]; then
        ((_SCORE += 40)); _TIER=1; _MARKERS="$_MARKERS .superclaude-metadata.json"
    fi
    if [[ -f "$dir/.skill-lock.json" ]]; then
        ((_SCORE += 40)); _TIER=1; _MARKERS="$_MARKERS .skill-lock.json"
    fi
    if [[ -f "$dir/.codex-global-state.json" ]]; then
        ((_SCORE += 35)); [[ $_TIER -gt 1 ]] && _TIER=1; _MARKERS="$_MARKERS .codex-global-state.json"
    fi
    if [[ -d "$dir/skills-cursor" ]]; then
        ((_SCORE += 35)); [[ $_TIER -gt 1 ]] && _TIER=1; _MARKERS="$_MARKERS skills-cursor/"
    fi
    # opencode.json with schema
    if [[ -f "$dir/opencode.json" ]] && grep -q 'schema.*opencode' "$dir/opencode.json" 2>/dev/null; then
        ((_SCORE += 40)); [[ $_TIER -gt 1 ]] && _TIER=1; _MARKERS="$_MARKERS opencode.json"
    fi

    # Tier 2: AI tool config files
    if [[ -f "$dir/mcp.json" ]]; then
        ((_SCORE += 25)); [[ $_TIER -gt 2 ]] && _TIER=2; _MARKERS="$_MARKERS mcp.json"
    fi
    # Agent-related subdirectories
    for subdir in agents rules prompts; do
        if [[ -d "$dir/$subdir" ]]; then
            ((_SCORE += 15)); [[ $_TIER -gt 2 ]] && _TIER=2; _MARKERS="$_MARKERS ${subdir}/"
            break  # count once
        fi
    done

    # Tier 3: settings.json with AI keys
    if [[ -f "$dir/settings.json" ]]; then
        if grep -qE '"(model|provider|api_key|enabledPlugins)"' "$dir/settings.json" 2>/dev/null; then
            ((_SCORE += 15)); [[ $_TIER -gt 3 ]] && _TIER=3; _MARKERS="$_MARKERS settings.json(ai)"
        fi
    fi
    # Tool documentation files
    for doc in GEMINI.md AGENTS.md CLAUDE.md; do
        if [[ -f "$dir/$doc" ]]; then
            ((_SCORE += 10)); [[ $_TIER -gt 3 ]] && _TIER=3; _MARKERS="$_MARKERS $doc"
            break
        fi
    done
    # config.toml (used by codex and others)
    if [[ -f "$dir/config.toml" ]]; then
        ((_SCORE += 10)); [[ $_TIER -gt 3 ]] && _TIER=3; _MARKERS="$_MARKERS config.toml"
    fi

    # Tier 4: skills/ directory (supporting evidence only)
    if [[ -d "$dir/skills" ]]; then
        ((_SCORE += 10)); _MARKERS="$_MARKERS skills/"
        # Check if skills are skillctl-managed symlinks
        local sample
        sample=$(find "$dir/skills" -maxdepth 1 -type l 2>/dev/null | head -1)
        if [[ -n "$sample" ]]; then
            local target
            target=$(readlink "$sample" 2>/dev/null)
            if [[ "$target" == *".skills/all/"* ]]; then
                ((_SCORE += 10)); _MARKERS="$_MARKERS skillctl-managed"
            fi
        fi
    fi

    # Trim leading space from markers
    _MARKERS="${_MARKERS# }"
}

# Compute relative symlink prefix from a skills_dir to $HOME/.skills/all
_compute_link_prefix() {
    local skills_dir="$1"
    local home="$HOME"
    # Count path segments from $HOME to skills_dir
    local rel="${skills_dir#$home/}"
    local depth
    depth=$(echo "$rel" | tr '/' '\n' | wc -l | tr -d ' ')
    local prefix=""
    local i
    for ((i = 0; i < depth; i++)); do
        prefix="../$prefix"
    done
    echo "${prefix}.skills/all"
}

# ─── Scan functions ─────────────────────────────────────────────────────

# Check if a name is in the exclude list
_is_excluded() {
    local name="$1"
    local excludes
    if [[ ${#SCAN_EXCLUDE[@]} -gt 0 ]]; then
        excludes=("${SCAN_EXCLUDE[@]}")
    else
        excludes=("${_DEFAULT_SCAN_EXCLUDE[@]}")
    fi
    for ex in "${excludes[@]}"; do
        # Exact match or prefix match (for patterns like .skills-backup*)
        [[ "$name" == "$ex" || "$name" == "$ex"-* ]] && return 0
    done
    return 1
}

# Check if a tool is in the disabled list (persisted in config.json)
_is_disabled() {
    local name="$1"
    if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
        jq -e --arg n "$name" '.disabled_tools // [] | index($n) != null' "$CONFIG_FILE" &>/dev/null && return 0
    fi
    return 1
}

# Scan results stored as lines: "name|path|skills_dir|type|prefix|score|tier|markers"
_SCAN_RESULTS=""

_scan_dotfile_dirs() {
    for dir in "$HOME"/.*; do
        [[ -d "$dir" ]] || continue
        local name
        name=$(basename "$dir")
        [[ "$name" == "." || "$name" == ".." ]] && continue
        # Remove leading dot for the tool name
        local tool_name="${name#.}"
        _is_excluded "$name" && continue
        _is_excluded "$tool_name" && continue
        _is_disabled "$tool_name" && continue

        _score_directory "$dir" "$tool_name"

        if [[ $_SCORE -ge 25 ]]; then
            local skills_dir="$dir/skills"
            local prefix
            prefix=$(_compute_link_prefix "$skills_dir")
            _SCAN_RESULTS+="${tool_name}|${dir}|${skills_dir}|dotfile|${prefix}|${_SCORE}|${_TIER}|${_MARKERS}"$'\n'
        fi
    done
}

_scan_config_dirs() {
    [[ -d "$HOME/.config" ]] || return
    for dir in "$HOME/.config"/*/; do
        [[ -d "$dir" ]] || continue
        local name
        name=$(basename "$dir")
        _is_excluded "$name" && continue
        _is_disabled "$name" && continue

        _score_directory "$dir" "$name"

        if [[ $_SCORE -ge 25 ]]; then
            local skills_dir="$dir/skills"  # note: dir already has trailing /
            skills_dir="${dir%/}/skills"
            local prefix
            prefix=$(_compute_link_prefix "$skills_dir")
            _SCAN_RESULTS+="${name}|${dir%/}|${skills_dir}|config|${prefix}|${_SCORE}|${_TIER}|${_MARKERS}"$'\n'
        fi
    done
}

# ─── Diff against existing config ──────────────────────────────────────

_diff_results() {
    # Compare scan results with loaded TOOL_NAMES
    local new_tools="" existing_tools="" gone_tools=""

    # Build set of scanned tool names
    local scanned_names=""
    while IFS='|' read -r tname _ _ _ _ _ _ _; do
        [[ -z "$tname" ]] && continue
        scanned_names+=" $tname "
    done <<< "$_SCAN_RESULTS"

    # Find new tools (in scan but not in config)
    while IFS='|' read -r tname _ _ _ _ _ _ _; do
        [[ -z "$tname" ]] && continue
        local found=false
        for existing in "${TOOL_NAMES[@]}"; do
            [[ "$existing" == "$tname" ]] && found=true && break
        done
        if [[ "$found" == "false" ]]; then
            new_tools+=" $tname"
        else
            existing_tools+=" $tname"
        fi
    done <<< "$_SCAN_RESULTS"

    # Find gone tools (in config but not in scan)
    for existing in "${TOOL_NAMES[@]}"; do
        if [[ "$scanned_names" != *" $existing "* ]]; then
            gone_tools+=" $existing"
        fi
    done

    _NEW_TOOLS="${new_tools# }"
    _EXISTING_TOOLS="${existing_tools# }"
    _GONE_TOOLS="${gone_tools# }"
}

# ─── Build and save config ──────────────────────────────────────────────

_build_config_json() {
    local default_mode="${SETTINGS_DEFAULT_SYNC_MODE:-all}"

    python3 -c "
import json, sys, os
from datetime import datetime, timezone

home = os.environ['HOME']
results_raw = '''$_SCAN_RESULTS'''.strip()
default_mode = '$default_mode'
existing_modes_raw = '${_EXISTING_MODES:-}'

# Parse existing modes (tool:mode pairs)
existing_modes = {}
if existing_modes_raw:
    for pair in existing_modes_raw.split():
        if ':' in pair:
            t, m = pair.split(':', 1)
            existing_modes[t] = m

# Parse existing selected skills
existing_selected_raw = '${_EXISTING_SELECTED:-}'
existing_selected = {}
if existing_selected_raw:
    for pair in existing_selected_raw.split('|'):
        if ':' in pair:
            t, skills_str = pair.split(':', 1)
            existing_selected[t] = skills_str.split() if skills_str else []

# Parse existing protected paths
existing_protected_raw = '${_EXISTING_PROTECTED:-}'
existing_protected = {}
if existing_protected_raw:
    for pair in existing_protected_raw.split('|'):
        if ':' in pair:
            t, paths_str = pair.split(':', 1)
            existing_protected[t] = paths_str.split(':') if paths_str else []

tools = {}
for line in results_raw.split('\n'):
    if not line.strip():
        continue
    parts = line.split('|', 7)
    if len(parts) < 8:
        continue
    name, path, skills_dir, ttype, prefix, score, tier, markers = parts

    # Determine sync_mode: preserve existing, else default
    mode = existing_modes.get(name, default_mode)
    selected = existing_selected.get(name, [])
    protected = existing_protected.get(name, [])

    # Normalize paths with ~
    path_short = path.replace(home, '~', 1)
    sd_short = skills_dir.replace(home, '~', 1)

    tools[name] = {
        'path': path_short,
        'skills_dir': sd_short,
        'type': ttype,
        'link_prefix': prefix,
        'sync_mode': mode,
        'selected_skills': selected,
        'protected_paths': protected,
        'detection': {
            'confidence': min(int(score), 100),
            'markers': markers.split(),
            'tier': int(tier),
        },
    }

# Preserve disabled_tools from existing config
existing_disabled = []
config_path = os.path.expanduser('$CONFIG_FILE')
if os.path.isfile(config_path):
    try:
        with open(config_path) as ef:
            existing_disabled = json.load(ef).get('disabled_tools', [])
    except:
        pass

config = {
    'version': 2,
    'last_scan_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'tools': dict(sorted(tools.items())),
    'disabled_tools': existing_disabled,
    'scan_exclude': [
        '.ssh', '.npm', '.docker', '.rbenv', '.pyenv', '.nvm', '.gradle',
        '.cache', '.local', '.vscode', '.Trash', '.zsh_sessions',
        '.cocoapods', '.gem', '.pub-cache', '.conda', '.mono',
        '.cups', '.thumbnails', '.matplotlib', '.ipython', '.jupyter',
    ],
    'settings': {
        'default_sync_mode': default_mode,
        'auto_scan_on_sync': False,
        'warn_on_new_tools': True,
    },
}

print(json.dumps(config, indent=2, ensure_ascii=False))
"
}

# ─── cmd_scan ───────────────────────────────────────────────────────────

cmd_scan() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --enable)
                _set_disabled "$2" false
                log_ok "Re-enabled: $2 (will appear in future scans)"
                return
                ;;
            --disable)
                _set_disabled "$2" true
                log_ok "Disabled: $2 (will skip in future scans)"
                return
                ;;
            --list-disabled)
                if [[ -f "$CONFIG_FILE" ]]; then
                    local disabled
                    disabled=$(jq -r '.disabled_tools // [] | if length == 0 then "  (none)" else .[] | "  \(.)" end' "$CONFIG_FILE" 2>/dev/null)
                    echo "$disabled"
                else
                    echo "  (none)"
                fi
                return
                ;;
            *) shift ;;
        esac
    done

    log_info "Scanning for AI tools..."

    _SCAN_RESULTS=""
    _scan_dotfile_dirs
    _scan_config_dirs

    local tool_count=0
    while IFS='|' read -r tname tpath _ _ _ tscore ttier tmarkers; do
        [[ -z "$tname" ]] && continue
        ((tool_count++))
        local tier_label=""
        case "$ttier" in
            1) tier_label="${GREEN}tier 1${RESET}" ;;
            2) tier_label="${CYAN}tier 2${RESET}" ;;
            3) tier_label="${YELLOW}tier 3${RESET}" ;;
            *) tier_label="${DIM}tier 4${RESET}" ;;
        esac
        log "  Found: ${BOLD}$tname${RESET}  $tpath  ($tier_label, ${tscore}%)"
    done <<< "$_SCAN_RESULTS"

    if [[ $tool_count -eq 0 ]]; then
        log_warn "No AI tools found."
        return 1
    fi
    log ""
    log_info "$tool_count AI tools discovered."

    # If config exists, do a diff
    if [[ ${#TOOL_NAMES[@]} -gt 0 ]]; then
        _diff_results

        # Preserve existing modes and selected skills for the config builder
        _EXISTING_MODES=""
        for t in "${TOOL_NAMES[@]}"; do
            _tool_index "$t" || continue
            _EXISTING_MODES+="$t:${TOOL_SYNC_MODES[$_IDX]:-all} "
        done

        _EXISTING_SELECTED=""
        for t in "${TOOL_NAMES[@]}"; do
            _tool_index "$t" || continue
            _EXISTING_SELECTED+="$t:${TOOL_SELECTED[$_IDX]:-}|"
        done

        _EXISTING_PROTECTED=""
        for t in "${TOOL_NAMES[@]}"; do
            _tool_index "$t" || continue
            _EXISTING_PROTECTED+="$t:${TOOL_PROTECTED[$_IDX]:-}|"
        done

        if [[ -n "$_NEW_TOOLS" ]]; then
            log ""
            log_info "New tools: ${BOLD}$_NEW_TOOLS${RESET}"
        fi
        if [[ -n "$_GONE_TOOLS" ]]; then
            log_warn "Gone tools: $_GONE_TOOLS"
        fi
    else
        _EXISTING_MODES=""
        _EXISTING_SELECTED=""
        _EXISTING_PROTECTED=""
    fi

    # Save config
    _scan_save

    log ""
    log "Run ${CYAN}skillctl tools${RESET} to manage sync modes interactively."

    # Prompt to enter tools TUI if running interactively
    if [[ -t 0 && "$QUIET" != "true" ]]; then
        echo ""
        echo -n "  Enter tools manager now? [Y/n]: "
        read -r yn
        yn=$(echo "$yn" | tr '[:upper:]' '[:lower:]')
        if [[ "$yn" != "n" ]]; then
            cmd_tools
        fi
    fi
}

_scan_save() {
    local config_json
    config_json=$(_build_config_json)

    if [[ "$DRY_RUN" == "true" ]]; then
        log_action "Would write config.json"
        echo "$config_json"
        return
    fi

    bash "$LIB_DIR/config_writer.sh" "$CONFIG_FILE" write_full "$config_json"
    log_ok "Config saved to $CONFIG_FILE"
    load_config
}




_set_disabled() {
    local name="$1"
    local disable="${2:-true}"
    [[ ! -f "$CONFIG_FILE" ]] && return
    local updated
    if [[ "$disable" == "true" ]]; then
        updated=$(jq --arg n "$name" \
            '.disabled_tools = ((.disabled_tools // []) + [$n] | unique | sort)' "$CONFIG_FILE")
    else
        updated=$(jq --arg n "$name" \
            '.disabled_tools = [(.disabled_tools // [])[] | select(. != $n)]' "$CONFIG_FILE")
    fi
    echo "$updated" > "$CONFIG_FILE.tmp.$$" && mv "$CONFIG_FILE.tmp.$$" "$CONFIG_FILE"
}
