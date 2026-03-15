# skillctl

Unified skill directory manager for AI coding tools.

Auto-discovers AI tools on your system and federates a single `~/.skills/` directory to all of them via symlinks. Each tool can be configured independently: sync all skills, a selection, or none.

## Quick Start

```bash
git clone <repo> ~/Documents/devs/skillctl
cd ~/Documents/devs/skillctl
./install.sh

# Add to ~/.zshrc or ~/.bashrc:
export PATH="$HOME/.skills/bin:$PATH"
```

Then:
```bash
skillctl scan    # Discover AI tools on your system
skillctl sync    # Apply symlinks to all tools
skillctl         # Interactive management TUI
```

## How It Works

```
~/.skills/                         # Single source of truth
├── user/          (44 skills)     # Your custom skills
├── utility/       (3 skills)      # Core tools (find-skills, skill-creator, etc.)
├── vendor/codex/  (28 skills)     # Vendor-curated (playwright, pdf, jupyter, etc.)
├── all/           (75 links)      # Auto-generated flat index
├── config.json                    # Discovered tools + per-tool sync config
├── .registry.json                 # Skill metadata
└── bin/skillctl                   # This tool

~/.<tool>/skills/                  # Symlinks → ~/.skills/all/*
```

### Auto-Discovery

`skillctl scan` examines `~/.*` and `~/.config/*` directories using a multi-signal scoring engine:

| Signal | Score | Example |
|--------|-------|---------|
| Known AI tool name | +20 | claude, cursor, codex, gemini, ... |
| Tool-specific metadata | +35-40 | `.superclaude-metadata.json`, `.codex-global-state.json` |
| AI config files | +25 | `mcp.json`, `opencode.json` |
| Agent subdirectories | +15 | `agents/`, `rules/`, `prompts/` |
| AI keys in settings | +15 | `model`, `provider`, `api_key` |
| skills/ directory | +10 | Supporting evidence only |

Threshold: score >= 25 to be recognized as an AI tool. After scanning, you can interactively remove false positives or add custom paths.

### Per-Tool Sync Modes

| Mode | Behavior |
|------|----------|
| `all` | Sync every skill (default) |
| `selective` | Only sync chosen skills |
| `ignore` | Skip completely |
| `external` | Tool manages its own skills (e.g., Gemini uses .agents) |

## Usage

```bash
# Interactive TUI (default command)
skillctl

# Discover AI tools
skillctl scan

# List tools and their sync modes
skillctl tools

# Configure a tool
skillctl tools set gemini external
skillctl tools set cursor selective
skillctl tools select cursor data-analysis deep-researcher

# Sync symlinks (respects per-tool config)
skillctl sync

# Health check
skillctl status

# List/search skills
skillctl list
skillctl list data

# Add / remove skills
skillctl add ./my-new-skill/
skillctl remove old-skill-name

# Fix issues
skillctl doctor

# Preview without changes
skillctl --dry-run sync
```

## Skill Format

Each skill follows the [open agent skills](https://github.com/anthropics/skills) convention:

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
├── bin/skillctl           # CLI entry point
├── lib/
│   ├── config.sh          # Config loading, tool data arrays
│   ├── config_loader.py   # JSON → bash variable converter
│   ├── config_writer.py   # Atomic JSON writer
│   ├── discover.sh        # AI tool auto-discovery engine
│   ├── tools.sh           # Per-tool configuration commands
│   ├── sync.sh            # Core sync: all/ index + tool dirs
│   ├── manage.sh          # status, list, add, remove, doctor
│   ├── registry.sh        # .registry.json management
│   ├── utils.sh           # Logging, colors, file helpers
│   └── tui.sh             # Interactive TUI (fzf + bash menu)
├── install.sh             # Symlink installer
└── tests/                 # Shell tests
```

## Requirements

- bash 3.2+ (macOS default works)
- python3 (for JSON handling)
- fzf (optional, for enhanced skill browser)

## License

MIT
