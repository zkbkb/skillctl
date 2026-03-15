#!/usr/bin/env bash
# config_writer.sh — Atomic JSON config writer using jq
# Usage:
#   config_writer.sh <config_path> write_full <json_string>
#   config_writer.sh <config_path> set_tool_mode <tool> <mode>
#   config_writer.sh <config_path> set_tool_skills <tool> <skill1> [skill2 ...]
#   config_writer.sh <config_path> remove_tool <tool>

set -euo pipefail

CONFIG_PATH="$1"
ACTION="$2"
shift 2

atomic_write() {
    local tmp="${CONFIG_PATH}.tmp.$$"
    echo "$1" > "$tmp"
    mv "$tmp" "$CONFIG_PATH"
}

case "$ACTION" in
    write_full)
        atomic_write "$1"
        ;;
    set_tool_mode)
        tool="$1"; mode="$2"
        updated=$(jq --arg t "$tool" --arg m "$mode" \
            '.tools[$t].sync_mode = $m' "$CONFIG_PATH")
        atomic_write "$updated"
        ;;
    set_tool_skills)
        tool="$1"; shift
        skills_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)
        updated=$(jq --arg t "$tool" --argjson s "$skills_json" \
            '.tools[$t].selected_skills = $s | .tools[$t].sync_mode = "selective"' "$CONFIG_PATH")
        atomic_write "$updated"
        ;;
    remove_tool)
        tool="$1"
        updated=$(jq --arg t "$tool" 'del(.tools[$t])' "$CONFIG_PATH")
        atomic_write "$updated"
        ;;
    *)
        echo "Unknown action: $ACTION" >&2
        exit 1
        ;;
esac
