#!/bin/zsh
set -euo pipefail

# Kiln is a pure CLI. The OpenAI-compatible backend is installed and managed
# separately, so this script only installs the command symlink.

ROOT="${0:A:h}"
BIN="${KILN_BIN:-$HOME/.local/bin/kiln}"
mkdir -p "${BIN:h}"
ln -sf "$ROOT/kiln" "$BIN"

print "Installed kiln CLI at $BIN"
print "Backend: set KILN_BASE_URL and KILN_API_KEY for your OpenAI-compatible server."
