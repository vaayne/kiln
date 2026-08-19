#!/usr/bin/env python3
import json, os, sys, time, urllib.request

URL = os.environ.get("MLX_URL", "http://127.0.0.1:8007") + "/v1/chat/completions"
KEY = open(os.path.expanduser(
    os.environ.get("MLX_API_KEY_FILE", "~/.config/kiln/api-key"))).read().strip()
MODEL = os.environ.get("MLX_AGENT_MODEL", "mlx-community/Qwen3.8-27B-4bit")

SHORT = "请写一篇关于 Apple Silicon 统一内存架构的详细技术文章。"
LONG_CTX = ("MLX 是 Apple 推出的机器学习框架,针对 Apple Silicon 优化。" * 300
            + "\n\n请基于以上背景,写一篇详细的技术分析文章。")

def run(prompt, max_tokens=400):
    body = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0,
        "stream": True,
        "stream_options": {"include_usage": True},
    }).encode()
    req = urllib.request.Request(URL, data=body, headers={
        "Content-Type": "application/json", "Authorization": f"Bearer {KEY}"})
    t0 = time.monotonic()
    t_first = None
    usage = None
    with urllib.request.urlopen(req, timeout=600) as resp:
        for line in resp:
            line = line.decode().strip()
            if not line.startswith("data: "):
                continue
            payload = line[6:]
            if payload == "[DONE]":
                break
            chunk = json.loads(payload)
            if chunk.get("usage"):
                usage = chunk["usage"]
            if chunk.get("choices") and t_first is None:
                delta = chunk["choices"][0].get("delta", {})
                if delta.get("content") or delta.get("reasoning_content"):
                    t_first = time.monotonic()
    t_end = time.monotonic()
    pt = usage["prompt_tokens"]; ct = usage["completion_tokens"]
    ttft = t_first - t0
    decode_tps = (ct - 1) / (t_end - t_first) if t_end > t_first else 0
    prefill_tps = pt / ttft
    return pt, ct, ttft, prefill_tps, decode_tps

def bench(name, prompt, rounds=3):
    print(f"== {name} ==")
    for i in range(rounds):
        pt, ct, ttft, ptps, dtps = run(prompt)
        print(f"  run{i+1}: prompt={pt} gen={ct} ttft={ttft:.2f}s "
              f"prefill={ptps:.0f} tok/s decode={dtps:.1f} tok/s")

if __name__ == "__main__":
    run(SHORT, 32)  # warmup
    bench("short prompt", SHORT)
    bench("long prompt (~4k ctx)", LONG_CTX)
