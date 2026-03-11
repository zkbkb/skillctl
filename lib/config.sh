#!/usr/bin/env bash
# config.sh — Tool directory registry and path configuration

# Categories within ~/.skills/
CATEGORY_USER="user"
CATEGORY_UTILITY="utility"
CATEGORY_VENDOR="vendor"

# Protected paths that must never be touched
PROTECTED_PATHS=(
    ".cursor/skills-cursor"
    ".codex/skills/.system"
)

# Tool directories under $HOME that have a skills/ subdirectory.
# Format: <relative-path-from-home>:<depth-to-home>
# depth-to-home is how many "../" needed from the skills/ dir to reach $HOME
#   e.g., ~/.foo/skills/ needs "../../" (depth 2) to reach ~/.skills/all/
#         ~/.config/foo/skills/ needs "../../../" (depth 3)

# Dotfile tools (depth 2: ~/.<tool>/skills/ → ../../.skills/all/)
DOTFILE_TOOLS=(
    adal agents claude cline codex commandcode continue copilot
    cursor factory gemini iflow junie kilocode kiro kode
    mcpjam moltbot mux neovate pochi qoder qwen roo
    trae trae-cn vibe zencoder
)

# Config tools (depth 3: ~/.config/<tool>/skills/ → ../../../.skills/all/)
CONFIG_TOOLS=(
    agents crush goose opencode
)

# Special: .augment uses "rules" not "skills"
# AUGMENT_TOOL="augment"

# Get the relative path prefix from a tool's skills/ dir to ~/.skills/all/
get_link_prefix() {
    local tool_type="$1"  # "dotfile" or "config"
    case "$tool_type" in
        dotfile) echo "../../.skills/all" ;;
        config)  echo "../../../.skills/all" ;;
        *)       echo "../../.skills/all" ;;
    esac
}

# Check if a path is protected
is_protected() {
    local path="$1"
    for p in "${PROTECTED_PATHS[@]}"; do
        if [[ "$path" == *"$p"* ]]; then
            return 0
        fi
    done
    return 1
}
