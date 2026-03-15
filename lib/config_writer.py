#!/usr/bin/env python3
"""Safely read/modify/write skillctl config.json.

Usage:
  python3 config_writer.py <config_path> write_full <json_string>
  python3 config_writer.py <config_path> set_tool_mode <tool> <mode>
  python3 config_writer.py <config_path> set_tool_skills <tool> <skill1> [skill2 ...]
  python3 config_writer.py <config_path> remove_tool <tool>
"""
import json, sys, os, tempfile
from datetime import datetime, timezone

def atomic_write(path, data):
    """Write JSON atomically: write to temp file, then rename."""
    content = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(content)
        os.rename(tmp, path)
    except:
        os.unlink(tmp)
        raise

def load(path):
    with open(path) as f:
        return json.load(f)

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def main():
    config_path = sys.argv[1]
    action = sys.argv[2]

    if action == "write_full":
        data = json.loads(sys.argv[3])
        data["updated_at"] = now_iso()
        atomic_write(config_path, data)

    elif action == "set_tool_mode":
        tool, mode = sys.argv[3], sys.argv[4]
        valid_modes = ("all", "selective", "ignore", "external")
        if mode not in valid_modes:
            print(f"Invalid mode: {mode}. Must be one of: {', '.join(valid_modes)}", file=sys.stderr)
            sys.exit(1)
        data = load(config_path)
        if tool not in data.get("tools", {}):
            print(f"Tool not found: {tool}", file=sys.stderr)
            sys.exit(1)
        data["tools"][tool]["sync_mode"] = mode
        data["updated_at"] = now_iso()
        atomic_write(config_path, data)

    elif action == "set_tool_skills":
        tool = sys.argv[3]
        skills = sys.argv[4:]
        data = load(config_path)
        if tool not in data.get("tools", {}):
            print(f"Tool not found: {tool}", file=sys.stderr)
            sys.exit(1)
        data["tools"][tool]["selected_skills"] = list(skills)
        if data["tools"][tool].get("sync_mode") != "selective":
            data["tools"][tool]["sync_mode"] = "selective"
        data["updated_at"] = now_iso()
        atomic_write(config_path, data)

    elif action == "remove_tool":
        tool = sys.argv[3]
        data = load(config_path)
        data.get("tools", {}).pop(tool, None)
        data["updated_at"] = now_iso()
        atomic_write(config_path, data)

    else:
        print(f"Unknown action: {action}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
