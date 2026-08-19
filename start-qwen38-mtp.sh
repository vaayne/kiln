#!/bin/zsh
set -euo pipefail

source "${0:A:h}/config.sh"

export PATH="$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export MLX_VLM_SERVER_API_KEY="$(< "$MLX_API_KEY_FILE")"

exec "$MLX_VLM_SERVER_BIN" \
  --host "$MLX_HOST" \
  --port "$MLX_PORT" \
  --model "$MLX_AGENT_MODEL" \
  --draft-model "$MLX_AGENT_DRAFT_MODEL" \
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
