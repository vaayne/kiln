#!/bin/zsh
set -euo pipefail

source "${0:A:h}/config.sh"
UV="${UV:-$(command -v uv || true)}"

if [[ -z "$UV" ]]; then
  print -u2 "uv is required: https://docs.astral.sh/uv/getting-started/installation/"
  exit 1
fi

print "[1/5] Installing MLX-VLM and Kiln gateway dependencies..."
"$UV" tool install --force --with jinja2 --with "fastapi>=0.115" --with "uvicorn[standard]>=0.30" --with "httpx>=0.27" mlx-vlm@latest

print "[2/5] Creating the isolated PaddleOCR environment..."
"$UV" venv --allow-existing --python 3.12 "$KILN_PADDLE_ENV"

print "[3/5] Installing PaddlePaddle CPU runtime..."
"$UV" pip install --python "$KILN_PADDLE_PYTHON" \
  paddlepaddle==3.2.1 \
  --index-url https://www.paddlepaddle.org.cn/packages/stable/cpu/

print "[4/5] Installing the PaddleOCR document parser..."
"$UV" pip install --python "$KILN_PADDLE_PYTHON" \
  'paddleocr[doc-parser]>=3.6.0' \
  python-docx

print "[5/5] Installing the launchd service..."
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" "${KILN_API_KEY_FILE:h}"
ln -sf "$KILN_ROOT/kiln" "$HOME/.local/bin/kiln"

domain="gui/$(id -u)"
plist="$HOME/Library/LaunchAgents/$KILN_LABEL.plist"
sed -e "s|__ROOT__|$KILN_ROOT|g" -e "s|__HOME__|$HOME|g" \
  "$KILN_ROOT/launchd/$KILN_LABEL.plist.in" > "$plist"
launchctl bootout "$domain/$KILN_LABEL" 2>/dev/null || true
# launchd needs a moment to release the label before it can be bootstrapped again.
sleep 1
launchctl bootstrap "$domain" "$plist" || {
  sleep 2
  launchctl bootstrap "$domain" "$plist"
}
launchctl kickstart -k "$domain/$KILN_LABEL"

print "Installed. Run: kiln doctor"
