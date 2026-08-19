#!/bin/zsh
# The single source of truth for every path, port and model name. install.sh,
# kiln and verify.sh all read from here; nothing below may be duplicated.

export MLX_ROOT="${MLX_ROOT:-$(cd "$(dirname "${(%):-%N}")" && pwd)}"
export MLX_SERVER_BIN="${MLX_SERVER_BIN:-$HOME/.local/bin/mlx_vlm.server}"
export MLX_API_KEY_FILE="${MLX_API_KEY_FILE:-$HOME/.config/kiln/api-key}"

# One server serves all three capabilities; models are selected per request.
export MLX_HOST="${MLX_HOST:-127.0.0.1}"
export MLX_PORT="${MLX_PORT:-8007}"
export MLX_URL="http://$MLX_HOST:$MLX_PORT"
export MLX_AGENT_MODEL="${MLX_AGENT_MODEL:-mlx-community/Qwen3.8-27B-4bit}"
export MLX_AGENT_DRAFT_MODEL="${MLX_AGENT_DRAFT_MODEL:-mlx-community/Qwen3.8-27B-MTP-4bit}"
export MLX_EMBED_MODEL="${MLX_EMBED_MODEL:-mlx-community/Qwen3-Embedding-4B-4bit-DWQ}"
export MLX_OCR_VLM_MODEL="${MLX_OCR_VLM_MODEL:-PaddlePaddle/PaddleOCR-VL-1.6}"

export MLX_PADDLE_ENV="${MLX_PADDLE_ENV:-$MLX_ROOT/.venv-paddleocr}"
export MLX_PADDLE_PYTHON="$MLX_PADDLE_ENV/bin/python"
export MLX_PADDLEOCR_BIN="$MLX_PADDLE_ENV/bin/paddleocr"

export MLX_LABEL="local.kiln.server"
export MLX_LOG="$HOME/Library/Logs/kiln.server.log"
