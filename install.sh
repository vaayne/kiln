#!/bin/zsh
set -euo pipefail

source "${0:A:h}/config.sh"
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

print "[5/5] Installing the launchd service..."
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" "${MLX_API_KEY_FILE:h}"
ln -sf "$MLX_ROOT/kiln" "$HOME/.local/bin/kiln"

domain="gui/$(id -u)"
plist="$HOME/Library/LaunchAgents/$MLX_LABEL.plist"
sed -e "s|__ROOT__|$MLX_ROOT|g" -e "s|__HOME__|$HOME|g" \
  "$MLX_ROOT/launchd/$MLX_LABEL.plist.in" > "$plist"
launchctl bootout "$domain/$MLX_LABEL" 2>/dev/null || true
# launchd needs a moment to release the label before it can be bootstrapped again.
sleep 1
launchctl bootstrap "$domain" "$plist" || {
  sleep 2
  launchctl bootstrap "$domain" "$plist"
}
launchctl kickstart -k "$domain/$MLX_LABEL"

print "Installed. Run: kiln doctor"
