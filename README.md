# skillctl

Unified skill directory manager for AI coding tools.

Manages a single canonical `~/.skills/` directory and federates symlinks to 30+ AI tool skill directories (Claude Code, Codex, Cursor, Copilot, Gemini, etc.), eliminating duplication and broken links.

## Problem

Modern AI coding tools each maintain their own `~/.<tool>/skills/` directory. With 28+ tools installed, this creates:

- **Scattered skills** across 3 separate real sources (`~/.claude/skills/`, `~/.agents/skills/`, `~/.codex/skills/`)
- **100+ redundant symlinks** pointing in different directions
- **Broken links** from naming inconsistencies (spaces vs hyphens, case mismatches)
- **No single place** to add, remove, or audit skills

## Solution

```
~/.skills/                         # Single source of truth
├── user/          (44 skills)     # Your custom skills
├── utility/       (3 skills)      # Core tools (find-skills, skill-creator, sonoscli)
├── vendor/codex/  (28 skills)     # Vendor-curated (playwright, pdf, jupyter, etc.)
├── all/           (75 links)      # Auto-generated flat index
├── bin/skillctl                   # This tool
└── .registry.json                 # Skill metadata

~/.<tool>/skills/                  # Every tool gets symlinks → ~/.skills/all/*
```

## Install

```bash
git clone <repo> ~/Documents/devs/skillctl
cd ~/Documents/devs/skillctl
./install.sh
```

This symlinks `skillctl` into `~/.skills/bin/`. Add to your shell profile:

```bash
export PATH="$HOME/.skills/bin:$PATH"
```

## Usage

```bash
# Health check — see counts, broken links, drift
skillctl status

# Re-sync all tool directories after changes
skillctl sync

# List all skills (with optional filter)
skillctl list
skillctl list data

# Add a new skill
skillctl add ./my-new-skill/

# Remove a skill
skillctl remove old-skill-name

# Diagnose and fix issues
skillctl doctor

# Interactive management (TUI)
skillctl manage

# Preview changes without applying
skillctl --dry-run sync
```

## How It Works

### Directory Structure

Skills are organized by provenance:

| Category | Path | Description |
|----------|------|-------------|
| `user/` | `~/.skills/user/` | Your own skills |
| `utility/` | `~/.skills/utility/` | Core ecosystem tools |
| `vendor/<name>/` | `~/.skills/vendor/codex/` | Vendor-curated skills |

The `all/` directory is a **flat index** — auto-generated symlinks that unify all categories into one namespace. Tool directories link into `all/`, not directly into category dirs.

### Symlink Federation

Each tool's `skills/` directory contains relative symlinks:

```
~/.claude/skills/playwright → ../../.skills/all/playwright
~/.config/opencode/skills/playwright → ../../../.skills/all/playwright
```

Relative paths ensure portability. The depth adjusts automatically based on directory nesting.

### Priority

When names conflict across categories: **user > utility > vendor**.

### Protected Paths

These are never touched:
- `~/.cursor/skills-cursor/` (Cursor-managed built-in skills)
- `~/.codex/skills/.system/` (Codex internal state)

## Supported Tools

Currently manages skills for **32 tool directories**:

**Dotfile tools:** adal, agents, claude, cline, codex, commandcode, continue, copilot, cursor, factory, gemini, iflow, junie, kilocode, kiro, kode, mcpjam, moltbot, mux, neovate, pochi, qoder, qwen, roo, trae, trae-cn, vibe, zencoder

**Config tools:** agents, crush, goose, opencode

## Adding New Tools

Edit `lib/config.sh` to add a tool to `DOTFILE_TOOLS` or `CONFIG_TOOLS`, then run `skillctl sync`.

## Skill Format

Each skill is a directory following the [open agent skills](https://github.com/anthropics/skills) convention:

```
my-skill/
├── SKILL.md          # Required: YAML frontmatter + markdown body
├── scripts/          # Optional: executable helpers
├── references/       # Optional: docs, schemas, specs
└── assets/           # Optional: templates, images
```

## Project Structure

```
skillctl/
├── bin/skillctl       # CLI entry point
├── lib/
│   ├── config.sh      # Tool registry, paths, constants
│   ├── utils.sh       # Logging, colors, file helpers
│   ├── registry.sh    # .registry.json management
│   ├── sync.sh        # Core sync: rebuild all/ + tool dirs
│   └── manage.sh      # Commands: status, list, add, remove, doctor
├── install.sh         # Symlink installer
└── tests/             # Shell tests
```

## License

MIT
