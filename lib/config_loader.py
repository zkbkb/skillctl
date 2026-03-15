#!/usr/bin/env python3
"""Read skillctl config.json and emit bash variable assignments.
DEPRECATED: Only used as fallback if jq is unavailable.
Prefer config_loader_jq() in config.sh.
"""
import json, sys, os

def shell_escape(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$').replace('`', '\\`')

def main():
    config_path = sys.argv[1]
    home = os.environ.get("HOME", "")
    with open(config_path) as f:
        config = json.load(f)
    tools = config.get("tools", {})
    def expand(path):
        if not path: return ""
        return path.replace("~", home, 1) if path.startswith("~") else path
    names = sorted(tools.keys())
    print(f'TOOL_NAMES=({" ".join(names)})')
    for array_name, key in [
        ("TOOL_PATHS", "path"), ("TOOL_SKILLS_DIRS", "skills_dir"),
        ("TOOL_PREFIXES", "link_prefix"), ("TOOL_SYNC_MODES", "sync_mode"),
        ("TOOL_TYPES", "type"),
    ]:
        vals = [f'"{shell_escape(expand(tools[n].get(key, "")))}"' for n in names]
        print(f'{array_name}=({" ".join(vals)})')
    vals = [f'"{shell_escape(":".join(tools[n].get("protected_paths", [])))}"' for n in names]
    print(f'TOOL_PROTECTED=({" ".join(vals)})')
    vals = [f'"{shell_escape(" ".join(tools[n].get("selected_skills", [])))}"' for n in names]
    print(f'TOOL_SELECTED=({" ".join(vals)})')
    settings = config.get("settings", {})
    for key, val in settings.items():
        print(f'SETTINGS_{key.upper().replace("-", "_")}="{shell_escape(str(val).lower())}"')
    excludes = config.get("scan_exclude", [])
    print(f'SCAN_EXCLUDE=({" ".join(shell_escape(e) for e in excludes)})')

if __name__ == "__main__":
    main()
