# Local MLX

一个面向 Apple Silicon 的本地 AI 能力包：Agent、Embedding 和 PaddleOCR-VL 文档解析统一由 launchd 管理。

## 安装

需要 macOS、Apple Silicon、[uv](https://docs.astral.sh/uv/) 和网络访问 Hugging Face。

```bash
cd ~/workspace/mlx-local
./install.sh
```

安装脚本会：

1. 用 `uv tool install --force --with jinja2 mlx-vlm@latest` 安装 MLX-VLM。
2. 创建独立的 Python 3.12 PaddleOCR 环境，避免和 MLX 的 Python 3.14 环境冲突。
3. 安装 PaddlePaddle CPU runtime 和 `paddleocr[doc-parser]`。
4. 安装并启动唯一的 MLX-VLM launchd 服务。

首次使用会从 Hugging Face 下载模型。

## 常用命令

```bash
./mlx-local doctor
./mlx-local chat '解释一下什么是 RAG'
./mlx-local embed '这段文字用于向量检索'
./mlx-local ocr ./invoice.pdf
./mlx-local logs -f
./mlx-local unload
./mlx-local service restart
```

`doctor` 会列出服务当前实际加载了哪些模型，是判断内存占用的第一手依据。`ocr` 默认输出到当前目录的 `./ocr-output`，可用 `--output` 指定。

## 服务布局

| 能力 | 地址 | 后端 |
| --- | --- | --- |
| Agent / Chat | `127.0.0.1:8007` | Qwen3.8-27B + MTP |
| Embedding | `127.0.0.1:8007/v1/embeddings` | Qwen3-Embedding-4B，按需加载 |
| OCR VLM | `127.0.0.1:8007/v1/chat/completions` | PaddleOCR-VL-1.6，按需加载 |

OCR 不是直接请求 VLM。完整流程由 PaddleOCR 在 CPU 上负责版面检测、阅读顺序和结果输出，MLX-VLM 只作为 VLM 识别后端。这是 PaddleOCR 官方 Apple Silicon 推荐的集成方式。

## HTTP endpoints

所有 endpoint 都在 `127.0.0.1:8007`，需要 `api-key`：

```bash
curl -H "Authorization: Bearer $(< api-key)" http://127.0.0.1:8007/health
curl -H "Authorization: Bearer $(< api-key)" http://127.0.0.1:8007/v1/models
```

主要接口：

| Endpoint | 用途 |
| --- | --- |
| `/v1/chat/completions` | Agent、文本/图片对话，也可直接指定 PaddleOCR-VL 模型 |
| `/v1/embeddings` | OpenAI-compatible 文本向量，指定 Qwen3 Embedding 模型 |
| `/health` | 服务状态和当前加载的模型 |
| `/v1/models` | 可用模型列表 |
| `/unload` | 释放当前模型缓存，给下一类能力让内存 |

直接调用 Embedding：

```bash
curl -X POST http://127.0.0.1:8007/v1/embeddings \
  -H "Authorization: Bearer $(< api-key)" \
  -H 'Content-Type: application/json' \
  -d '{"model":"mlx-community/Qwen3-Embedding-4B-4bit-DWQ","input":["hello","你好"]}'
```

Agent 客户端可直接使用 OpenAI-compatible 配置：

```text
base_url = http://127.0.0.1:8007/v1
api_key  = <~/.config/mlx-local/api-key 的内容>
model    = mlx-community/Qwen3.8-27B-4bit
```

## 文件说明

| 文件 | 用途 |
| --- | --- |
| `config.sh` | 端口、模型名和路径的唯一来源 |
| `mlx-local` | 统一命令入口 |
| `verify.sh` | 回归验收，改动后跑它 |
| `install.sh` | 安装依赖并注册 launchd |
| `launchd/*.plist.in` | launchd 模板，安装时展开到 `~/Library/LaunchAgents` |
| `AGENTS.md` | 改动这套东西时的约定和陷阱 |

## 内存与延迟

这是一个 HTTP server，不是三个常驻服务，平时只有 Agent 模型占内存。代价是同一时刻只保留一个生成模型：交替使用 chat 和 OCR 时，每次切换都要重建 worker，大约 10~15 秒。`mlx-local` 会自动等待重试，用别的客户端直连 API 则需要自己重试。

内存压力变高时，先释放按需加载的模型，退回到只保留 Agent：

```bash
./mlx-local unload
```

要完全让出内存，停掉服务：

```bash
./mlx-local service stop
```

`api-key` 存放在 `~/.config/mlx-local/api-key`，不进入仓库，也不要写入日志或文档。改动这套配置前先读 `AGENTS.md`。
