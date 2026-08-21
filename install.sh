#!/bin/zsh
set -euo pipefail

# Kiln is a pure CLI. The OpenAI-compatible backend is installed and managed
# separately; this script installs only the CLI runtime and command symlink.

ROOT="${0:A:h}"
BIN="${KILN_BIN:-$HOME/.local/bin/kiln}"
VENV="${KILN_VENV:-$ROOT/.venv-kiln}"
UV="${UV:-$(command -v uv || true)}"

if [[ -z "$UV" ]]; then
  print -u2 "uv is required to install Kiln's Python dependencies: https://docs.astral.sh/uv/"
  exit 1
fi

print "[1/2] Installing Kiln CLI dependencies..."
"$UV" venv --allow-existing --python 3.12 "$VENV"
"$UV" pip install --python "$VENV/bin/python" -r "$ROOT/requirements.txt"

print "[2/2] Installing the kiln command..."
mkdir -p "${BIN:h}"
ln -sf "$ROOT/kiln" "$BIN"

print "Installed kiln CLI at $BIN"
print "Python runtime: $VENV/bin/python"
print "Backend: set KILN_BASE_URL and KILN_API_KEY for your OpenAI-compatible server."
