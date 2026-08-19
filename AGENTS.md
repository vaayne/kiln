# Local MLX 运行约定

这是 Apple Silicon 上的本地 AI 能力包，不是单个模型脚本。只有一个 HTTP server，按 endpoint 和请求模型名提供能力。

## 能力与端口

| 能力 | launchd Label | 地址 | 模型/后端 |
| --- | --- | --- | --- |
| Agent / Chat | `local.mlx-vlm.qwen38-mtp` | `127.0.0.1:8007` | Qwen3.8-27B-4bit + MTP |
| Embedding | 同一 server 的 `/v1/embeddings` | `127.0.0.1:8007` | Qwen3-Embedding-4B，按需加载 |
| OCR VLM | 同一 server 的 `/v1/chat/completions` | `127.0.0.1:8007` | PaddleOCR-VL-1.6，按需加载 |

完整 OCR 不直接请求 VLM。PaddleOCR 在 CPU 上负责版面检测、阅读顺序和结果保存，MLX-VLM 只作为识别后端。这是 PaddleOCR 官方 Apple Silicon 集成方式。

只有一个 HTTP server。Agent 的 Qwen 启动时预加载；Embedding 和 OCR 在请求里显式传模型名，首次调用时按需加载。生成模型切换时 server 会重建 worker，通常会有约 10~15 秒冷启动窗口；`mlx-local` 会自动重试，但直接调用 HTTP API 的客户端也应实现重试。统一入口是 `mlx-local`，安装后位于 `~/.local/bin/mlx-local`。源码入口和配置在本目录：`mlx-local`、`config.sh`。

## 安装与升级

需要 macOS、Apple Silicon、`uv` 和 Hugging Face 网络访问。完整安装只执行：

```bash
cd ~/.config/mlx-vlm
./install.sh
```

安装脚本会：

1. 用 `uv tool install --force --with jinja2 mlx-vlm@latest` 安装 MLX-VLM。`jinja2` 是 chat template 的运行时依赖，不能漏。
2. 在 `.venv-paddleocr` 创建独立 Python 3.12 环境。
3. 安装 `paddlepaddle==3.2.1` CPU 版、`paddleocr[doc-parser]>=3.6.0` 和 `python-docx`。
4. 展开唯一的 Agent launchd plist，注册并启动 HTTP server。

不要把 PaddleOCR 依赖装进 MLX-VLM 的 uv tool，也不要把 `jinja2` 装进系统 Python。

升级 MLX-VLM：

```bash
uv tool install --force --with jinja2 mlx-vlm@latest
mlx-local service restart
```

升级后必须跑 `mlx-local doctor` 和最小请求，不要只看进程是否存在。

## 当前 Agent 参数

`start-qwen38-mtp.sh` 的基线参数：

```text
--draft-kind mtp
--draft-block-size 3
--kv-bits 8
--quantized-kv-start 2048
--max-kv-size 65536
--max-num-seqs 1
--prefill-step-size 2048
--max-tokens 16384
--enable-thinking
```

这些参数针对 48GB M5 Pro MacBook Pro 的单人日常使用调过。`draft-block-size` 不要改成 4，实测解码速度明显下降；2 没有收益。`--thinking-budget` 不可与 MTP speculative decoding 同时使用，服务端会直接报错。

## 常用命令

```bash
mlx-local doctor
mlx-local chat '只回复 OK'
mlx-local embed '用于 RAG 检索的文本'
mlx-local ocr ./invoice.pdf --output ./ocr-output
mlx-local logs -n 100
mlx-local unload
mlx-local service restart
mlx-local service stop
mlx-local service status
```

`doctor` 输出包含服务当前加载的模型分组，排查内存和模型切换问题先看它。模型名、端口和路径只在 `config.sh` 定义一次，`start-qwen38-mtp.sh` 和 `mlx-local` 都从那里读，不要在别处硬编码。

Agent API 兼容 OpenAI `/v1/chat/completions`，Embedding 兼容 `/v1/embeddings`。三类请求共用本目录的 `api-key`，服务只监听 localhost。

## 性能与内存

Agent 短 prompt 基线约 25 tok/s，4.8K prompt 解码约 22~24 tok/s。连续压测会受到日常应用内存占用和积热影响，比较参数前冷却约 3 分钟并使用相同请求。

所有能力共享一个 HTTP server 和统一内存。Agent 预加载，Embedding/OCR 按需动态加载；首次调用它们会有冷启动延迟。

`mlx-local unload` 释放按需加载的模型；服务会重建 worker 并重新预加载 Agent，等价于回到基线占用。彻底让出内存用 `mlx-local service stop`。

模型原生上下文约 256K，Agent 当前 `max-kv-size=65536`。64K 以内完整保留，超过上限会 rotating KV 静默覆盖旧上下文，不会返回错误，不能把它当作无限上下文使用。

## OCR 注意事项

OCR 首次启动会下载 `PaddlePaddle/PaddleOCR-VL-1.6` 和 PaddleOCR 的版面模型，首次调用还可能下载字体。完整文档解析比直接 VLM 看图慢，但会保留布局、表格和 Markdown/JSON/DOCX 输出。

`mlx-local ocr` 默认输出到当前目录的 `./ocr-output`，失败时把服务端/客户端错误打到 stderr；成功时只打印输出目录，避免把整份结构化结果刷满终端。输入路径在调用 PaddleOCR 前先校验，路径错会直接报错而不是抛 PaddleOCR 的 worker traceback。

## launchd

只有 Agent HTTP server 由 launchd 管理，模板在 `launchd/local.mlx-vlm.qwen38-mtp.plist.in`，安装时展开到 `~/Library/LaunchAgents`。手动重启：

```bash
launchctl kickstart -k gui/$(id -u)/local.mlx-vlm.qwen38-mtp
```

日志位于 `~/Library/Logs/mlx-vlm-*.log`。修改启动脚本后必须重启对应服务。

## 安全

`api-key` 是密钥，已被 `.gitignore` 排除。不要读取后写入文档、日志、提交或回复中。模型缓存和 OCR 输出也不提交。
