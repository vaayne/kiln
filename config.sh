#!/bin/zsh

export MLX_VLM_ROOT="${MLX_VLM_ROOT:-$(cd "$(dirname "${(%):-%N}")" && pwd)}"
export MLX_VLM_SERVER_BIN="${MLX_VLM_SERVER_BIN:-$HOME/.local/bin/mlx_vlm.server}"

export MLX_AGENT_URL="${MLX_AGENT_URL:-http://127.0.0.1:8007}"
export MLX_AGENT_MODEL="${MLX_AGENT_MODEL:-mlx-community/Qwen3.8-27B-4bit}"
export MLX_EMBED_URL="${MLX_EMBED_URL:-$MLX_AGENT_URL}"
export MLX_EMBED_MODEL="${MLX_EMBED_MODEL:-mlx-community/Qwen3-Embedding-4B-4bit-DWQ}"
export MLX_OCR_VLM_URL="${MLX_OCR_VLM_URL:-$MLX_AGENT_URL}"
export MLX_OCR_VLM_MODEL="${MLX_OCR_VLM_MODEL:-PaddlePaddle/PaddleOCR-VL-1.6}"
export MLX_PADDLE_ENV="${MLX_PADDLE_ENV:-$MLX_VLM_ROOT/.venv-paddleocr}"
export MLX_PADDLE_PYTHON="$MLX_PADDLE_ENV/bin/python"
export MLX_PADDLEOCR_BIN="$MLX_PADDLE_ENV/bin/paddleocr"
export MLX_AGENT_LABEL="local.mlx-vlm.qwen38-mtp"
export MLX_QWEN_LABEL="local.mlx-vlm.qwen38-mtp"
export MLX_EMBED_LABEL="$MLX_AGENT_LABEL"
