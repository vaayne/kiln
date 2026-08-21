---
name: kiln-cli
description: Use Kiln as a pure OpenAI-compatible CLI for local chat, translation, embeddings, OCR, model listing, and backend health checks. Trigger whenever the user asks to use a local model, translate text, generate embeddings, OCR an image, inspect available models, or diagnose the local API.
compatibility: Requires the `kiln` executable and an OpenAI-compatible backend reachable through `KILN_BASE_URL`.
---

# Kiln CLI

Kiln is only an API client. It does not start, stop, restart, unload, configure, or supervise the backend. Do not use launchd commands, `kiln service`, `kiln serve`, `kiln unload`, or `kiln config`; those are no longer CLI commands.

Keep the API key private. Never print it, copy it into an artifact, or put it in a shell command shown to the user. The local default key is `local`; use `KILN_API_KEY` or `KILN_API_KEY_FILE` when the backend expects another value.

## Environment

```zsh
export KILN_BASE_URL=http://127.0.0.1:8007
export KILN_API_KEY=local
export KILN_MODEL=ornith-ai--Ornith-1.5-35B-A3B-MLX-4bit
export KILN_OCR_MODEL=Unlimited-OCR-mxfp8
export KILN_EMBEDDING_MODEL=mlx-community--Qwen3-Embedding-4B-4bit-DWQ
export KILN_TRANSLATE_MODEL=Hy-MT2-1.8B-4bit
```

OCR and translation fall back to `KILN_MODEL` when their specific model variable is unset. Embeddings have no fallback and fail clearly when `KILN_EMBEDDING_MODEL` is unset.

`rich` is a direct CLI dependency installed by `./install.sh` into `.venv-kiln`. TTY output gets Markdown and table rendering; pipes stay machine-readable. Use `KILN_RICH=never` to force plain output or `KILN_RICH=always` to force rich rendering. `KILN_PYTHON` can override the managed Python runtime.

## Safe start

Run `kiln doctor` before an operation that depends on the backend when availability is uncertain. If it is down, report the endpoint and ask the user to repair or start the backend externally. Do not run backend recovery commands on Kiln's behalf.

The CLI retries transient 5xx and connection failures for 12 attempts, 3 seconds apart by default. Do not add a competing retry loop. Override with `KILN_RETRIES` and `KILN_RETRY_DELAY` only when needed.

## Commands

### Chat

```zsh
kiln chat '解释一下什么是 RAG'
cat document.txt | kiln chat
```

It sends one user message to `/v1/chat/completions` using `KILN_MODEL` and prints plain assistant text. stdin is preferred for long or multiline input.

### Translation

```zsh
kiln translate '今天天气不错。'
kiln translate --lang 中文 'The weather is nice today.'
```

The default target is English; `--lang` or `-l` selects another target language. The CLI adds a translation-only instruction because Hy-MT2 otherwise may behave like a general chat model. Override it with `KILN_TRANSLATE_INSTRUCTION`.

### Embeddings

```zsh
kiln embed '这段文字用于向量检索'
cat document.txt | kiln embed
```

It sends to `/v1/embeddings` using `KILN_EMBEDDING_MODEL` and prints raw OpenAI-compatible JSON. Do not paste large vectors into a normal response; report count and dimension unless raw JSON was requested.

### OCR

```zsh
kiln ocr ./invoice.png
kiln ocr '只输出图片中的文字' ./invoice.png
kiln ocr https://example.com/image.png
```

OCR sends a multimodal request to `/v1/chat/completions` using `KILN_OCR_MODEL`. Local images become data URLs; HTTP(S) image URLs are passed through. The default instruction is `请识别图片中的全部文字并原样输出`; override it with `KILN_OCR_INSTRUCTION` or a positional instruction.

OCR prints the model response. It does not run PaddleOCR and does not create Markdown, JSON, DOCX, layout PNG, or an output directory. PDF and office containers are rejected; convert them to images first.

### Models and health

```zsh
kiln models
kiln doctor
```

`models` lists `/v1/models` ids. In a TTY it uses a Rich table when available; pipes receive one id per line. `doctor` prints `/health` JSON, or a Rich table in a TTY. Neither command exposes the API key.

### Logs

Kiln does not own backend logs. `kiln logs` only works when `KILN_LOG` points to an existing backend log file:

```zsh
KILN_LOG=/path/to/backend.log kiln logs -f
```

## Failure handling

- Missing image or invalid syntax: show the corrected `kiln` command; do not guess a path.
- Backend unavailable: report the configured endpoint and ask for external backend recovery.
- Missing embedding model: tell the user to set `KILN_EMBEDDING_MODEL`; never fall back to a chat model.
- OCR failure: preserve the input and report the backend error. There is no Kiln-managed output directory.
- API-key errors: do not inspect or repeat the key; ask the user to repair their local environment.

## Final report

**→ Result.** What completed or failed.

**→ Backend.** Endpoint and model only if relevant, never the secret.

**→ Output.** Plain text, JSON path, or OCR result location if applicable.
