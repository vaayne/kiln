#!/usr/bin/env python3
"""Validated, secret-free configuration shared by the shell CLI and gateway."""
from __future__ import annotations

import json
import re
import shlex
import sys
import tempfile
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError as exc:  # Python 3.11+ is part of Kiln's install contract.
    raise SystemExit("Kiln requires Python 3.11 or newer to read config.toml") from exc

MODEL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$")
DEFAULTS: dict[str, dict[str, Any]] = {
    "server": {"host": "127.0.0.1", "port": 8007, "upstream_port": 8017},
    "models": {
        "agent": "mlx-community/Qwen3.8-27B-4bit",
        "draft": "mlx-community/Qwen3.8-27B-MTP-4bit",
        "embedding": "mlx-community/Qwen3-Embedding-4B-4bit-DWQ",
        "ocr": "PaddlePaddle/PaddleOCR-VL-1.6",
    },
    "runtime": {
        "draft_kind": "mtp", "draft_block_size": 3, "kv_bits": 8,
        "quantized_kv_start": 2048, "max_kv_size": 65536,
        "enable_thinking": True, "max_tokens": 16384,
        "prefill_step_size": 2048, "vision_cache_size": 4,
        "max_num_seqs": 1, "log_progress_interval": 50,
    },
}


def _copy_defaults() -> dict[str, dict[str, Any]]:
    return {section: values.copy() for section, values in DEFAULTS.items()}


def validate(config: dict[str, Any]) -> dict[str, dict[str, Any]]:
    if set(config) != set(DEFAULTS):
        raise ValueError("config must contain server, models, and runtime sections only")
    result = _copy_defaults()
    for section, allowed in DEFAULTS.items():
        values = config.get(section)
        if not isinstance(values, dict) or set(values) != set(allowed):
            raise ValueError(f"{section} has missing or unknown settings")
        result[section].update(values)

    server = result["server"]
    if server["host"] != "127.0.0.1":
        raise ValueError("server.host is fixed to 127.0.0.1; Kiln is local-only")
    for key in ("port", "upstream_port"):
        if not isinstance(server[key], int) or not 1024 <= server[key] <= 65535:
            raise ValueError(f"server.{key} must be a user port")
    if server["port"] == server["upstream_port"]:
        raise ValueError("server.port and server.upstream_port must differ")

    for key, model in result["models"].items():
        if key == "draft" and model == "":
            continue
        if not isinstance(model, str) or not MODEL_RE.fullmatch(model):
            raise ValueError(f"models.{key} must be a Hugging Face model id")

    runtime = result["runtime"]
    if runtime["draft_kind"] not in ("", "dflash", "eagle3", "mtp"):
        raise ValueError("runtime.draft_kind must be mtp, dflash, eagle3, or blank")
    if bool(runtime["draft_kind"]) != bool(result["models"]["draft"]):
        raise ValueError("draft model and draft_kind must either both be set or both be blank")
    if not isinstance(runtime["enable_thinking"], bool):
        raise ValueError("runtime.enable_thinking must be true or false")
    kv_bits = runtime["kv_bits"]
    if isinstance(kv_bits, bool) or not isinstance(kv_bits, (int, float)) or not 1 <= kv_bits <= 16:
        raise ValueError("runtime.kv_bits must be a number from 1 to 16")
    ranges = {
        "draft_block_size": (1, 16),
        "quantized_kv_start": (0, 1_000_000), "max_kv_size": (1024, 1_000_000),
        "max_tokens": (1, 262_144), "prefill_step_size": (1, 65_536),
        "vision_cache_size": (0, 128), "max_num_seqs": (1, 16),
        "log_progress_interval": (0, 10_000),
    }
    for key, (minimum, maximum) in ranges.items():
        value = runtime[key]
        if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
            raise ValueError(f"runtime.{key} must be an integer from {minimum} to {maximum}")
    return result


def load(path: str | Path) -> dict[str, dict[str, Any]]:
    with Path(path).open("rb") as handle:
        return validate(tomllib.load(handle))


def _toml_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value, ensure_ascii=False)


def render(config: dict[str, dict[str, Any]]) -> str:
    lines = [
        "# Kiln's user-editable settings. `kiln config set` validates and rewrites this file.",
        "# Secrets remain in ~/.config/kiln/api-key and never belong here.",
        "",
    ]
    for section in ("server", "models", "runtime"):
        lines.append(f"[{section}]")
        lines.extend(f"{key} = {_toml_value(value)}" for key, value in config[section].items())
        lines.append("")
    return "\n".join(lines)


def write(path: str | Path, config: dict[str, Any]) -> dict[str, dict[str, Any]]:
    normalized = validate(config)
    target = Path(path)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=target.parent, delete=False) as handle:
        handle.write(render(normalized))
        temporary = Path(handle.name)
    temporary.replace(target)
    return normalized


def set_value(current: dict[str, dict[str, Any]], dotted_key: str, raw_value: str) -> dict[str, dict[str, Any]]:
    """Update one CLI-safe setting without exposing network binding controls."""
    section, separator, key = dotted_key.partition(".")
    if not separator or section not in {"models", "runtime"} or key not in current[section]:
        raise ValueError("setting must be a models.* or runtime.* key; run `kiln config show`")
    try:
        value = json.loads(raw_value)
    except json.JSONDecodeError:
        value = raw_value
    updated = _copy_defaults()
    for name, values in current.items():
        updated[name].update(values)
    updated[section][key] = value
    return validate(updated)


def shell_exports(config: dict[str, dict[str, Any]]) -> str:
    server, models, runtime = config["server"], config["models"], config["runtime"]
    values = {
        "KILN_HOST": server["host"], "KILN_PORT": server["port"],
        "KILN_UPSTREAM_PORT": server["upstream_port"],
        "KILN_AGENT_MODEL": models["agent"], "KILN_AGENT_DRAFT_MODEL": models["draft"],
        "KILN_EMBED_MODEL": models["embedding"], "KILN_OCR_VLM_MODEL": models["ocr"],
        "KILN_DRAFT_KIND": runtime["draft_kind"],
        "KILN_DRAFT_BLOCK_SIZE": runtime["draft_block_size"],
        "KILN_KV_BITS": runtime["kv_bits"],
        "KILN_QUANTIZED_KV_START": runtime["quantized_kv_start"],
        "KILN_MAX_KV_SIZE": runtime["max_kv_size"],
        "KILN_ENABLE_THINKING": runtime["enable_thinking"],
        "KILN_MAX_TOKENS": runtime["max_tokens"],
        "KILN_PREFILL_STEP_SIZE": runtime["prefill_step_size"],
        "KILN_VISION_CACHE_SIZE": runtime["vision_cache_size"],
        "KILN_MAX_NUM_SEQS": runtime["max_num_seqs"],
        "KILN_LOG_PROGRESS_INTERVAL": runtime["log_progress_interval"],
    }
    return "\n".join(f"export {key}={shlex.quote(str(value).lower() if isinstance(value, bool) else str(value))}" for key, value in values.items())


if __name__ == "__main__":
    command = sys.argv[1:]
    if len(command) == 2 and command[0] == "shell":
        print(shell_exports(load(command[1])))
    elif len(command) == 2 and command[0] == "show":
        print(render(load(command[1])), end="")
    elif len(command) == 4 and command[0] == "set":
        path, dotted_key, raw_value = command[1:]
        write(path, set_value(load(path), dotted_key, raw_value))
    else:
        raise SystemExit("usage: kiln_config.py {shell|show} CONFIG.toml | set CONFIG.toml SECTION.KEY VALUE")
