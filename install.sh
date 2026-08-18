#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/config.sh"
UV="${UV:-$(command -v uv || true)}"

if [[ -z "$UV" ]]; then
  print -u2 "uv is required: https://docs.astral.sh/uv/getting-started/installation/"
  exit 1
fi

print "[1/5] Installing mlx-vlm with the chat-template dependency..."
"$UV" tool install --force --with jinja2 mlx-vlm@latest

print "[2/5] Creating the isolated PaddleOCR environment..."
"$UV" venv --allow-existing --python 3.12 "$MLX_PADDLE_ENV"

print "[3/5] Installing PaddlePaddle CPU runtime..."
"$UV" pip install --python "$MLX_PADDLE_PYTHON" \
  paddlepaddle==3.2.1 \
  --index-url https://www.paddlepaddle.org.cn/packages/stable/cpu/

print "[4/5] Installing the PaddleOCR document parser..."
"$UV" pip install --python "$MLX_PADDLE_PYTHON" \
  'paddleocr[doc-parser]>=3.6.0' \
  python-docx

print "[5/5] Installing launchd agents..."
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
ln -sf "$ROOT/mlx-local" "$HOME/.local/bin/mlx-local"
launchctl bootout "gui/$(id -u)/local.mlx-vlm.embedding" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.mlx-vlm.embedding.plist"
launchctl bootout "gui/$(id -u)/local.mlx-vlm.paddleocr-vl" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.mlx-vlm.paddleocr-vl.plist"
for template in "$ROOT"/launchd/*.plist.in; do
  target="$HOME/Library/LaunchAgents/$(basename "$template" .in)"
  sed -e "s|__ROOT__|$ROOT|g" -e "s|__HOME__|$HOME|g" "$template" > "$target"
  label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$target")"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  sleep 1
  launchctl bootstrap "gui/$(id -u)" "$target" || {
    sleep 2
    launchctl bootstrap "gui/$(id -u)" "$target"
  }
  launchctl kickstart -k "gui/$(id -u)/$label"
done

print "Installed. Run: $ROOT/mlx-local doctor"
