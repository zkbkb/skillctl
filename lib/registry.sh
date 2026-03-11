#!/usr/bin/env bash
# registry.sh — .registry.json management

# Initialize an empty registry
registry_init() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_action "Create $REGISTRY_FILE"
        return
    fi
    cat > "$REGISTRY_FILE" <<'ENDJSON'
{
  "version": 1,
  "created_at": "",
  "skills": {}
}
ENDJSON
    # Patch in the timestamp
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Use python for JSON manipulation if available, else sed
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
with open('$REGISTRY_FILE', 'r') as f:
    data = json.load(f)
data['created_at'] = '$ts'
with open('$REGISTRY_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
    else
        sed -i '' "s/\"created_at\": \"\"/\"created_at\": \"$ts\"/" "$REGISTRY_FILE"
    fi
}

# Rebuild the registry from the filesystem
registry_rebuild() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_action "Rebuild $REGISTRY_FILE"
        return
    fi

    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    python3 -c "
import json, os, hashlib
from pathlib import Path

skills_root = os.path.expanduser('$SKILLS_ROOT')
registry = {
    'version': 1,
    'updated_at': '$ts',
    'skills': {}
}

categories = {
    'user': os.path.join(skills_root, 'user'),
    'utility': os.path.join(skills_root, 'utility'),
}

# Scan vendor subdirectories
vendor_dir = os.path.join(skills_root, 'vendor')
if os.path.isdir(vendor_dir):
    for vendor in sorted(os.listdir(vendor_dir)):
        vpath = os.path.join(vendor_dir, vendor)
        if os.path.isdir(vpath) and not vendor.startswith('.'):
            categories[f'vendor/{vendor}'] = vpath

for category, cat_path in sorted(categories.items()):
    if not os.path.isdir(cat_path):
        continue
    for skill_name in sorted(os.listdir(cat_path)):
        skill_path = os.path.join(cat_path, skill_name)
        if not os.path.isdir(skill_path) or skill_name.startswith('.'):
            continue
        skill_md = os.path.join(skill_path, 'SKILL.md')
        has_skill_md = os.path.isfile(skill_md)

        # Compute a simple hash of SKILL.md if it exists
        file_hash = ''
        if has_skill_md:
            with open(skill_md, 'rb') as f:
                file_hash = hashlib.sha256(f.read()).hexdigest()[:12]

        registry['skills'][skill_name] = {
            'category': category,
            'has_skill_md': has_skill_md,
            'hash': file_hash,
        }

with open(os.path.join(skills_root, '.registry.json'), 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)

print(f'Registry rebuilt: {len(registry[\"skills\"])} skills')
"
}

# Print registry summary
registry_summary() {
    if [[ ! -f "$REGISTRY_FILE" ]]; then
        log_warn "No registry found. Run 'skillctl sync' first."
        return
    fi
    python3 -c "
import json
with open('$REGISTRY_FILE') as f:
    data = json.load(f)
skills = data.get('skills', {})
cats = {}
for name, info in skills.items():
    cat = info.get('category', 'unknown')
    cats[cat] = cats.get(cat, 0) + 1
print(f'Total skills: {len(skills)}')
for cat in sorted(cats):
    print(f'  {cat}: {cats[cat]}')
"
}
