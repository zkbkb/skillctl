#!/usr/bin/env bash
set -euo pipefail

# install.sh — Install skillctl to ~/.skills/bin/ and add to PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.skills/bin"

echo "Installing skillctl..."

# Ensure ~/.skills/bin exists
mkdir -p "$INSTALL_DIR"

# Symlink the bin/skillctl to ~/.skills/bin/skillctl
if [[ -L "$INSTALL_DIR/skillctl" || -f "$INSTALL_DIR/skillctl" ]]; then
    rm "$INSTALL_DIR/skillctl"
fi
ln -s "$SCRIPT_DIR/bin/skillctl" "$INSTALL_DIR/skillctl"

# Symlink lib/ so the script can find it
if [[ -L "$INSTALL_DIR/../lib" ]]; then
    rm "$INSTALL_DIR/../lib"
fi
if [[ ! -d "$INSTALL_DIR/../lib" ]]; then
    ln -s "$SCRIPT_DIR/lib" "$INSTALL_DIR/../lib"
fi

echo "Installed: $INSTALL_DIR/skillctl → $SCRIPT_DIR/bin/skillctl"

# Check if ~/.skills/bin is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo "Add this to your ~/.zshrc or ~/.bashrc:"
    echo ""
    echo "  export PATH=\"\$HOME/.skills/bin:\$PATH\""
    echo ""
fi

echo "Done! Run 'skillctl --help' to get started."
