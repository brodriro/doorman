#!/bin/bash
# Copies the plugin into omarchy-shell's plugin dir (symlinks are rejected by
# the shell) and validates it. The shell hot-reloads on change.
# Usage: ./install.sh [--enable]
set -euo pipefail
cd "$(dirname "$0")"
id=$(jq -r .id manifest.json)
omarchy-plugin-validate .
rsync -a --delete --exclude .git --exclude tests --exclude docs --exclude CLAUDE.md --exclude install.sh --exclude .claude --exclude .gitignore ./ "$HOME/.config/omarchy/plugins/$id/"
omarchy-shell shell rescanPlugins >/dev/null
[[ ${1:-} == --enable ]] && omarchy plugin enable "$id" --section right
echo "installed $id"
