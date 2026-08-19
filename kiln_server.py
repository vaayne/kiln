#!/usr/bin/env python3
"""Kiln's single-port local gateway and MLX worker supervisor."""
from __future__ import annotations

import asyncio
import os
import signal
import subprocess
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

import httpx
import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
from starlette.background import BackgroundTask

from kiln_config import load

CONFIG_PATH = Path(os.environ["KILN_CONFIG_FILE"])
HOP_BY_HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade"}


def settings() -> dict[str, dict[str, Any]]:
    return load(CONFIG_PATH)


def service_key() -> str:
    path = Path(os.environ["KILN_API_KEY_FILE"])
    key = path.read_text(encoding="utf-8").strip()
    if not key:
        raise RuntimeError(f"API key is empty: {path}")
    return key


def worker_command(config: dict[str, dict[str, Any]]) -> list[str]:
    runtime, models, server = config["runtime"], config["models"], config["server"]
    command = [
        os.environ["MLX_SERVER_BIN"], "--host", "127.0.0.1", "--port", str(server["upstream_port"]),
        "--model", models["agent"], "--kv-bits", str(runtime["kv_bits"]),
        "--quantized-kv-start", str(runtime["quantized_kv_start"]),
        "--max-kv-size", str(runtime["max_kv_size"]), "--max-tokens", str(runtime["max_tokens"]),
        "--prefill-step-size", str(runtime["prefill_step_size"]),
        "--vision-cache-size", str(runtime["vision_cache_size"]),
        "--max-num-seqs", str(runtime["max_num_seqs"]),
        "--log-progress-interval", str(runtime["log_progress_interval"]),
    ]
    if runtime["enable_thinking"]:
        command.append("--enable-thinking")
    if models["draft"]:
        command.extend([
            "--draft-model", models["draft"], "--draft-kind", runtime["draft_kind"],
            "--draft-block-size", str(runtime["draft_block_size"]),
        ])
    return command


def start_worker() -> subprocess.Popen[bytes]:
    environment = os.environ.copy()
    environment["MLX_VLM_SERVER_API_KEY"] = service_key()
    environment["PATH"] = f"{Path.home()}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    return subprocess.Popen(worker_command(settings()), env=environment, start_new_session=True)


def stop_worker(worker: subprocess.Popen[bytes]) -> None:
    if worker.poll() is not None:
        return
    os.killpg(worker.pid, signal.SIGTERM)
    try:
        worker.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(worker.pid, signal.SIGKILL)
        worker.wait(timeout=5)


def upstream_url(path: str) -> str:
    config = settings()
    return f"http://127.0.0.1:{config['server']['upstream_port']}/{path.lstrip('/')}"


def proxy_headers(request: Request) -> dict[str, str]:
    headers = {key: value for key, value in request.headers.items() if key.lower() not in HOP_BY_HOP | {"host", "content-length"}}
    return headers


async def forward(request: Request, path: str) -> StreamingResponse:
    client: httpx.AsyncClient = request.app.state.client
    body = await request.body()
    upstream_request = client.build_request(request.method, upstream_url(path), headers=proxy_headers(request), content=body, params=request.query_params)
    try:
        response = await client.send(upstream_request, stream=True)
    except httpx.HTTPError as exc:
        raise HTTPException(503, "MLX worker is restarting") from exc
    response_headers = {key: value for key, value in response.headers.items() if key.lower() not in HOP_BY_HOP | {"content-length"}}
    return StreamingResponse(response.aiter_raw(), status_code=response.status_code, headers=response_headers, background=BackgroundTask(response.aclose))


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.client = httpx.AsyncClient(timeout=httpx.Timeout(connect=2, read=None, write=60, pool=5))
    app.state.worker = start_worker()
    try:
        yield
    finally:
        await app.state.client.aclose()
        stop_worker(app.state.worker)


app = FastAPI(title="Kiln", docs_url=None, redoc_url=None, lifespan=lifespan)


@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"])
async def public_api(path: str, request: Request) -> StreamingResponse:
    return await forward(request, path)


if __name__ == "__main__":
    configuration = settings()
    uvicorn.run(app, host=configuration["server"]["host"], port=configuration["server"]["port"], log_level="info", access_log=False)
