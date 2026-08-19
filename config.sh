#!/bin/zsh
# Shell bridge for config.toml. Paths and secrets stay here; user settings live
# in TOML so the CLI, launchd and gateway read exactly the same values.

export KILN_ROOT="${KILN_ROOT:-$(cd "$(dirname "${(%):-%N}")" && pwd)}"
export KILN_CONFIG_FILE="${KILN_CONFIG_FILE:-$HOME/.config/kiln/config.toml}"
export KILN_CONFIG_TEMPLATE="$KILN_ROOT/config.toml.example"
if [[ ! -f "$KILN_CONFIG_FILE" ]]; then
  mkdir -p "${KILN_CONFIG_FILE:h}"
  cp "$KILN_CONFIG_TEMPLATE" "$KILN_CONFIG_FILE"
fi
export MLX_SERVER_BIN="${MLX_SERVER_BIN:-$HOME/.local/bin/mlx_vlm.server}"
export KILN_API_KEY_FILE="${KILN_API_KEY_FILE:-$HOME/.config/kiln/api-key}"

# The MLX tool's Python has FastAPI and supports tomllib after install. A host
# Python 3.11+ is only used for the very first install.
if [[ -x "$HOME/.local/share/uv/tools/mlx-vlm/bin/python" ]]; then
  export KILN_PYTHON="${KILN_PYTHON:-$HOME/.local/share/uv/tools/mlx-vlm/bin/python}"
else
  export KILN_PYTHON="${KILN_PYTHON:-$(command -v python3)}"
fi
eval "$("$KILN_PYTHON" "$KILN_ROOT/kiln_config.py" shell "$KILN_CONFIG_FILE")"

export KILN_URL="http://$KILN_HOST:$KILN_PORT"
export KILN_PADDLE_ENV="${KILN_PADDLE_ENV:-$KILN_ROOT/.venv-paddleocr}"
export KILN_PADDLE_PYTHON="$KILN_PADDLE_ENV/bin/python"
export KILN_PADDLEOCR_BIN="$KILN_PADDLE_ENV/bin/paddleocr"
export KILN_LABEL="local.kiln.server"
export KILN_LOG="$HOME/Library/Logs/kiln.server.log"
