---
name: kiln-cli
description: Operate Kiln, a local Apple Silicon AI service, exclusively through its `kiln` command-line interface. Use this skill whenever the user asks to chat with Kiln, generate embeddings, OCR a PDF or image, inspect or change Kiln models/runtime settings, diagnose its local AI service, unload models, read Kiln logs, or control the Kiln launchd service. Prefer it even when the user only says “use my local model”, “run local OCR”, or “change the Qwen settings”.
compatibility: Requires macOS with the `kiln` executable installed and its local launchd service available.
---

# Kiln CLI

Use Kiln as a local capability service, not a browser application. Keep the API key in `~/.config/kiln/api-key`; never print, copy, pass it in a shell command, or put it in an artifact.

## Start safely

1. Resolve the executable with `command -v kiln`. If it is absent, say so and ask before running the repository's installer.
2. Run `kiln doctor` before an operation that depends on the service. If the service is down, report that and use `kiln service start` only when the user asked to operate Kiln or authorized recovery.
3. Report the command outcome, model-switch cost when relevant, and output path for files. Do not narrate secrets or dump embedding vectors unless the user requested them.

`kiln` already retries transient worker restarts for 12 attempts, 3 seconds apart. Do not add a competing retry loop.

## Commands

### Chat

Use `kiln chat 'prompt'` for a short prompt. For multiline or long content, pipe standard input so shell quoting and argument-size limits cannot corrupt it:

```zsh
cat <<'PROMPT' | kiln chat
Summarize this document in five Chinese bullets:
...
PROMPT
```

The command is single-turn. Preserve conversation context in the prompt only when the user supplied it. It prints plain assistant text.

### Embeddings

Use `kiln embed 'text'` or standard input. It prints OpenAI-compatible JSON. For normal work, report vector count and dimension rather than pasting thousands of floats. Save raw JSON only to a user-requested path.

Embedding loads an on-demand model. The next chat request may reload the agent model.

### OCR

Use `kiln ocr INPUT [--output DIR]`. Require an existing local file or an explicit HTTP(S) URL. Pick `--output` when the user specified a destination; otherwise tell them the default is `./ocr-output` before writing there. Successful OCR produces Markdown, JSON, DOCX, and layout PNG files.

OCR is slow and replaces the loaded generation model. Say that before starting a large document or batch. Do not treat OCR as direct VLM chat, Kiln intentionally delegates layout and reading order to PaddleOCR.

### Configuration

Use `kiln config show` to inspect validated, secret-free TOML settings.

Use `kiln config set SECTION.KEY VALUE` only for an explicit requested setting change. It accepts `models.*` and `runtime.*`, validates the complete file, atomically writes it, then restarts Kiln. State the 10–15 second interruption before changing a model or runtime setting. JSON literals preserve types:

```zsh
kiln config set runtime.enable_thinking false
kiln config set runtime.max_kv_size 32768
kiln config set models.draft ''
```

Do not edit `~/.config/kiln/config.toml` directly. Do not attempt to change `server.*`: Kiln is intentionally fixed to `127.0.0.1:8007`, with the worker private on `:8017`.

### Operations and recovery

- `kiln doctor`: binaries, health, loaded models, context limit.
- `kiln logs [-f] [-n LINES]`: launchd log. Avoid `-f` unless the user wants an ongoing session.
- `kiln unload`: release on-demand models and return to the agent baseline.
- `kiln service {start|stop|restart|status}`: manage the launchd service. Confirm before `stop` when it could interrupt active work.

Only one generation model remains resident. Alternating chat and OCR rebuilds the worker and costs roughly 10–15 seconds. A `max_kv_size` over 65536 silently rotates old context, so do not recommend it as an unlimited-context setting.

## Failure handling

- Missing input or invalid CLI syntax: show the exact corrected command, do not guess a file path.
- `doctor` reports the server down: suggest `kiln service start`; run it only with operational authorization.
- OCR failure: preserve the output directory and surface the last useful error. Do not delete user inputs or partial artifacts.
- Any error mentioning an API key: stop, do not inspect the key, and ask the user to repair `~/.config/kiln/api-key` locally.

## Final report

Use this compact format after an operation:

**→ Result.** What completed or failed.

**→ Kiln.** Loaded model or service state, only if it matters.

**→ Output.** File path or concise result, if applicable.
