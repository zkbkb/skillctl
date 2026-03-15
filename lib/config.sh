#!/usr/bin/env bash
# config.sh — Config-driven tool registry (v0.2.0)
# Uses indexed parallel arrays for bash 3.2+ compatibility.
# TOOL_NAMES[i] corresponds to TOOL_PATHS[i], TOOL_SYNC_MODES[i], etc.

# ─── Constants ──────────────────────────────────────────────────────────

CATEGORY_USER="user"
CATEGORY_UTILITY="utility"
CATEGORY_VENDOR="vendor"

CONFIG_FILE="${SKILLS_ROOT}/config.json"

# ─── Dynamic tool data (populated by load_config) ──────────────────────
# All arrays are parallel-indexed: index 0 in each array = same tool.

TOOL_NAMES=()
TOOL_PATHS=()
TOOL_SKILLS_DIRS=()
TOOL_PREFIXES=()
TOOL_SYNC_MODES=()
TOOL_TYPES=()
TOOL_PROTECTED=()
TOOL_SELECTED=()

# Settings
SETTINGS_DEFAULT_SYNC_MODE="all"
SETTINGS_AUTO_SCAN_ON_SYNC="false"
SETTINGS_WARN_ON_NEW_TOOLS="true"

# Scan exclude list
SCAN_EXCLUDE=()

# ─── Index lookup ───────────────────────────────────────────────────────
# Find the index of a tool by name. Returns via _IDX variable.

_tool_index() {
    local name="$1"
    local i
    for ((i = 0; i < ${#TOOL_NAMES[@]}; i++)); do
        if [[ "${TOOL_NAMES[$i]}" == "$name" ]]; then
            _IDX=$i
            return 0
        fi
    done
    _IDX=-1
    return 1
}

# ─── Config loading ─────────────────────────────────────────────────────

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        _load_legacy_config
        return 1
    fi
    # Prefer jq (4ms) over python3 (120ms)
    if command -v jq &>/dev/null; then
        _load_config_jq
    else
        eval "$(python3 "$LIB_DIR/config_loader.py" "$CONFIG_FILE" 2>/dev/null)" || {
            _load_legacy_config
            return 1
        }
    fi
    return 0
}

_load_config_jq() {
    local home="$HOME"

    TOOL_NAMES=()
    TOOL_PATHS=()
    TOOL_SKILLS_DIRS=()
    TOOL_PREFIXES=()
    TOOL_SYNC_MODES=()
    TOOL_TYPES=()
    TOOL_PROTECTED=()
    TOOL_SELECTED=()

    # Single jq call: extract all tool data as tab-separated lines
    while IFS=$'\t' read -r name path skills_dir prefix mode ttype protected selected; do
        [[ -z "$name" ]] && continue
        TOOL_NAMES+=("$name")
        TOOL_PATHS+=("${path//\~/$home}")
        TOOL_SKILLS_DIRS+=("${skills_dir//\~/$home}")
        TOOL_PREFIXES+=("$prefix")
        TOOL_SYNC_MODES+=("$mode")
        TOOL_TYPES+=("$ttype")
        TOOL_PROTECTED+=("$protected")
        TOOL_SELECTED+=("$selected")
    done < <(jq -r '.tools | to_entries | sort_by(.key)[] |
        [.key,
         .value.path,
         .value.skills_dir,
         .value.link_prefix,
         (.value.sync_mode // "all"),
         (.value.type // "dotfile"),
         (.value.protected_paths // [] | join(":")),
         (.value.selected_skills // [] | join(" "))
        ] | @tsv' "$CONFIG_FILE" 2>/dev/null)

    # Settings
    SETTINGS_DEFAULT_SYNC_MODE=$(jq -r '.settings.default_sync_mode // "all"' "$CONFIG_FILE" 2>/dev/null)
    SETTINGS_AUTO_SCAN_ON_SYNC=$(jq -r '.settings.auto_scan_on_sync // false' "$CONFIG_FILE" 2>/dev/null)
    SETTINGS_WARN_ON_NEW_TOOLS=$(jq -r '.settings.warn_on_new_tools // true' "$CONFIG_FILE" 2>/dev/null)

    # Scan exclude
    SCAN_EXCLUDE=()
    while IFS= read -r ex; do
        [[ -n "$ex" ]] && SCAN_EXCLUDE+=("$ex")
    done < <(jq -r '.scan_exclude // [] | .[]' "$CONFIG_FILE" 2>/dev/null)
}

# Legacy fallback: reconstruct old behavior when no config.json exists
_load_legacy_config() {
    [[ "$QUIET" != "true" ]] && log_warn "No config.json. Run 'skillctl scan' to create."

    TOOL_NAMES=()
    TOOL_PATHS=()
    TOOL_SKILLS_DIRS=()
    TOOL_PREFIXES=()
    TOOL_SYNC_MODES=()
    TOOL_TYPES=()
    TOOL_PROTECTED=()
    TOOL_SELECTED=()

    local legacy_dotfile=(
        adal agents claude cline codex commandcode continue copilot
        cursor factory iflow junie kilocode kiro kode
        mcpjam moltbot mux neovate pochi qoder qwen roo
        trae trae-cn vibe zencoder
    )
    for tool in "${legacy_dotfile[@]}"; do
        TOOL_NAMES+=("$tool")
        TOOL_PATHS+=("$HOME/.$tool")
        TOOL_SKILLS_DIRS+=("$HOME/.$tool/skills")
        TOOL_PREFIXES+=("../../.skills/all")
        TOOL_SYNC_MODES+=("all")
        TOOL_TYPES+=("dotfile")
        TOOL_PROTECTED+=("")
        TOOL_SELECTED+=("")
    done

    # Set protected paths for specific tools
    _tool_index "codex" && TOOL_PROTECTED[$_IDX]="skills/.system"
    _tool_index "cursor" && TOOL_PROTECTED[$_IDX]="skills-cursor"

    local legacy_config=(agents crush goose opencode)
    for tool in "${legacy_config[@]}"; do
        TOOL_NAMES+=("config-$tool")
        TOOL_PATHS+=("$HOME/.config/$tool")
        TOOL_SKILLS_DIRS+=("$HOME/.config/$tool/skills")
        TOOL_PREFIXES+=("../../../.skills/all")
        TOOL_SYNC_MODES+=("all")
        TOOL_TYPES+=("config")
        TOOL_PROTECTED+=("")
        TOOL_SELECTED+=("")
    done
}

# ─── Accessors (by tool name → look up index) ──────────────────────────
# These avoid repetitive _tool_index calls throughout the codebase.

tool_path()       { _tool_index "$1" && echo "${TOOL_PATHS[$_IDX]}"; }
tool_skills_dir() { _tool_index "$1" && echo "${TOOL_SKILLS_DIRS[$_IDX]}"; }
tool_prefix()     { _tool_index "$1" && echo "${TOOL_PREFIXES[$_IDX]}"; }
tool_sync_mode()  { _tool_index "$1" && echo "${TOOL_SYNC_MODES[$_IDX]:-all}"; }
tool_type()       { _tool_index "$1" && echo "${TOOL_TYPES[$_IDX]}"; }

# ─── Helpers ────────────────────────────────────────────────────────────

get_link_prefix() {
    local tool_type="$1"
    case "$tool_type" in
        dotfile) echo "../../.skills/all" ;;
        config)  echo "../../../.skills/all" ;;
        *)       echo "../../.skills/all" ;;
    esac
}

is_protected() {
    local tool="$1"
    local rel_path="$2"
    _tool_index "$tool" || return 1
    local protected="${TOOL_PROTECTED[$_IDX]}"
    [[ -z "$protected" ]] && return 1
    IFS=':' read -ra paths <<< "$protected"
    for p in "${paths[@]}"; do
        [[ "$rel_path" == *"$p"* ]] && return 0
    done
    return 1
}

get_tool_selected_skills() {
    local tool="$1"
    _tool_index "$tool" || return 1
    echo "${TOOL_SELECTED[$_IDX]}"
}
