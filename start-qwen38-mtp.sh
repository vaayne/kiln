#!/bin/zsh
set -euo pipefail

export PATH="$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export MLX_VLM_SERVER_API_KEY="$(< "$HOME/.config/mlx-vlm/api-key")"

exec "$HOME/.local/bin/mlx_vlm.server" \
  --host 127.0.0.1 \
  --port 8007 \
  --model mlx-community/Qwen3.8-27B-4bit \
  --draft-model mlx-community/Qwen3.8-27B-MTP-4bit \
  --draft-kind mtp \
  --draft-block-size 3 \
  --kv-bits 8 \
  --quantized-kv-start 2048 \
  --max-kv-size 65536 \
  --enable-thinking \
  --max-tokens 16384 \
  --prefill-step-size 2048 \
  --vision-cache-size 4 \
  --max-num-seqs 1 \
  --log-progress-interval 50
