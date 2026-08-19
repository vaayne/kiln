#!/usr/bin/env python3
"""Kiln's single-port local gateway, WebUI, and MLX worker supervisor."""
from __future__ import annotations

import asyncio
import os
import secrets
import shutil
import signal
import subprocess
import sys
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

import httpx
import uvicorn
from fastapi import Depends, FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse, StreamingResponse
from starlette.background import BackgroundTask

from kiln_config import load, merge, write

ROOT = Path(__file__).resolve().parent
CONFIG_PATH = Path(os.environ["KILN_CONFIG_FILE"])
UI_DIR = ROOT / "ui"
OCR_ROOT = Path.home() / ".cache" / "kiln" / "ui-ocr"
SESSION_TTL_SECONDS = 60 * 60
OCR_TTL_SECONDS = 24 * 60 * 60  # global cache; use per-user jobs if Kiln ever leaves localhost.
MAX_OCR_UPLOAD_BYTES = 100 * 1024 * 1024
ALLOWED_OCR_SUFFIXES = {".pdf", ".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"}
HOP_BY_HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade"}


def settings() -> dict[str, dict[str, Any]]:
    return load(CONFIG_PATH)


def service_key() -> str:
    path = Path(os.environ["KILN_API_KEY_FILE"])
    key = path.read_text(encoding="utf-8").strip()
    if not key:
        raise RuntimeError(f"API key is empty: {path}")
    return key


def authorized(request: Request) -> bool:
    header = request.headers.get("authorization", "")
    return header.startswith("Bearer ") and secrets.compare_digest(header[7:], service_key())


def require_bearer(request: Request) -> None:
    if not authorized(request):
        raise HTTPException(401, "invalid API key")


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


def proxy_headers(request: Request, *, inject_key: bool = False) -> dict[str, str]:
    headers = {key: value for key, value in request.headers.items() if key.lower() not in HOP_BY_HOP | {"host", "content-length"}}
    if inject_key:
        headers["authorization"] = f"Bearer {service_key()}"
    return headers


async def forward(request: Request, path: str, *, inject_key: bool = False) -> StreamingResponse:
    client: httpx.AsyncClient = request.app.state.client
    body = await request.body()
    upstream_request = client.build_request(request.method, upstream_url(path), headers=proxy_headers(request, inject_key=inject_key), content=body, params=request.query_params)
    try:
        response = await client.send(upstream_request, stream=True)
    except httpx.HTTPError as exc:
        raise HTTPException(503, "MLX worker is restarting") from exc
    response_headers = {key: value for key, value in response.headers.items() if key.lower() not in HOP_BY_HOP | {"content-length"}}
    return StreamingResponse(response.aiter_raw(), status_code=response.status_code, headers=response_headers, background=BackgroundTask(response.aclose))


def cleanup_ocr_cache() -> None:
    OCR_ROOT.mkdir(parents=True, exist_ok=True)
    cutoff = time.time() - OCR_TTL_SECONDS
    for child in OCR_ROOT.iterdir():
        if child.is_dir() and child.stat().st_mtime < cutoff:
            shutil.rmtree(child, ignore_errors=True)


def current_session(request: Request) -> None:
    token = request.cookies.get("kiln_ui_session")
    expires = request.app.state.ui_sessions.get(token or "", 0)
    if expires < time.time():
        request.app.state.ui_sessions.pop(token or "", None)
        raise HTTPException(401, "open the WebUI with `kiln ui`")


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.ui_sessions = {}
    app.state.client = httpx.AsyncClient(timeout=httpx.Timeout(connect=2, read=None, write=60, pool=5))
    app.state.worker = start_worker()
    try:
        yield
    finally:
        await app.state.client.aclose()
        stop_worker(app.state.worker)


app = FastAPI(title="Kiln", docs_url=None, redoc_url=None, lifespan=lifespan)


@app.post("/ui/api/session")
async def create_ui_session(request: Request) -> dict[str, str]:
    require_bearer(request)
    token = secrets.token_urlsafe(32)
    request.app.state.ui_sessions[token] = time.time() + SESSION_TTL_SECONDS
    return {"url": f"{os.environ['KILN_URL']}/ui?token={token}"}


@app.get("/ui")
async def ui(request: Request, token: str | None = None):
    if token:
        expiry = request.app.state.ui_sessions.pop(token, 0)
        if expiry >= time.time():
            response = RedirectResponse("/ui/", status_code=303)
            response.set_cookie("kiln_ui_session", token, httponly=True, samesite="strict", max_age=SESSION_TTL_SECONDS)
            request.app.state.ui_sessions[token] = expiry
            return response
    current_session(request)
    return FileResponse(UI_DIR / "index.html")


@app.get("/ui/")
async def ui_index(request: Request):
    current_session(request)
    return FileResponse(UI_DIR / "index.html")


@app.get("/ui/assets/{asset:path}")
async def ui_asset(asset: str, request: Request):
    current_session(request)
    candidate = (UI_DIR / asset).resolve()
    if UI_DIR.resolve() not in candidate.parents or not candidate.is_file():
        raise HTTPException(404, "asset not found")
    return FileResponse(candidate)


@app.get("/ui/api/settings")
async def get_settings(_: None = Depends(current_session)) -> dict[str, dict[str, Any]]:
    return settings()


@app.put("/ui/api/settings")
async def put_settings(update: dict[str, Any], _: None = Depends(current_session)) -> dict[str, Any]:
    try:
        saved = write(CONFIG_PATH, merge(settings(), update))
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    return {"settings": saved, "restart_required": True}


@app.post("/ui/api/restart")
async def restart(_: None = Depends(current_session)) -> dict[str, bool]:
    # Let the response flush. launchd KeepAlive recreates this gateway and its worker.
    loop = asyncio.get_running_loop()
    loop.call_later(0.5, os.kill, os.getpid(), signal.SIGTERM)
    return {"restarting": True}


@app.get("/ui/api/health")
async def ui_health(request: Request, _: None = Depends(current_session)) -> StreamingResponse:
    return await forward(request, "health", inject_key=True)


@app.post("/ui/api/chat")
async def ui_chat(request: Request, _: None = Depends(current_session)) -> StreamingResponse:
    return await forward(request, "v1/chat/completions", inject_key=True)


@app.post("/ui/api/embeddings")
async def ui_embeddings(request: Request, _: None = Depends(current_session)) -> StreamingResponse:
    return await forward(request, "v1/embeddings", inject_key=True)


@app.post("/ui/api/ocr")
async def ui_ocr(file: UploadFile = File(...), _: None = Depends(current_session)) -> dict[str, Any]:
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in ALLOWED_OCR_SUFFIXES:
        raise HTTPException(415, "OCR accepts PDF, PNG, JPG, WEBP, BMP, or TIFF files")
    cleanup_ocr_cache()
    task = secrets.token_urlsafe(12)
    output = OCR_ROOT / task
    output.mkdir(parents=True)
    source = output / f"source{suffix}"
    size = 0
    with source.open("wb") as handle:
        while chunk := await file.read(1024 * 1024):
            size += len(chunk)
            if size > MAX_OCR_UPLOAD_BYTES:
                shutil.rmtree(output, ignore_errors=True)
                raise HTTPException(413, "OCR upload limit is 100 MiB")
            handle.write(chunk)
    config = settings()
    command = [
        os.environ["KILN_PADDLEOCR_BIN"], "doc_parser", "--input", str(source),
        "--pipeline_version", "v1.6", "--device", "cpu", "--save_path", str(output),
        "--vl_rec_backend", "mlx-vlm-server", "--vl_rec_server_url", os.environ["KILN_URL"] + "/",
        "--vl_rec_api_model_name", config["models"]["ocr"], "--vl_rec_api_key", service_key(),
        "--vl_rec_max_concurrency", "1",
    ]
    completed = await asyncio.to_thread(subprocess.run, command, text=True, capture_output=True, timeout=900)
    if completed.returncode:
        print(f"PaddleOCR task failed with exit code {completed.returncode}", file=sys.stderr)
        raise HTTPException(502, "PaddleOCR failed")
    files = sorted(path.name for path in output.iterdir() if path.is_file() and path.name != source.name)
    markdown = next((path for path in output.glob("*.md")), None)
    return {
        "task": task,
        "files": files,
        "markdown": markdown.read_text(encoding="utf-8", errors="replace")[:1_000_000] if markdown else "",
    }


@app.get("/ui/api/ocr/{task}/{filename}")
async def ocr_download(task: str, filename: str, _: None = Depends(current_session)) -> FileResponse:
    if "/" in filename or not task.replace("-", "").replace("_", "").isalnum():
        raise HTTPException(404, "file not found")
    candidate = (OCR_ROOT / task / filename).resolve()
    if OCR_ROOT.resolve() not in candidate.parents or not candidate.is_file():
        raise HTTPException(404, "file not found")
    return FileResponse(candidate, filename=filename)


@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"])
async def public_api(path: str, request: Request) -> StreamingResponse:
    return await forward(request, path)


if __name__ == "__main__":
    configuration = settings()
    uvicorn.run(app, host=configuration["server"]["host"], port=configuration["server"]["port"], log_level="info", access_log=False)
