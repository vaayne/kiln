# Kiln CLI

Kiln 是一个纯 CLI，用 OpenAI-compatible API 调用本地 omlx 后端。Kiln 不启动、重启或配置后端，也不依赖 `config.sh`、launchd 或 PaddleOCR。

默认后端地址：`http://127.0.0.1:8007`。

## 安装

需要 macOS 和 zsh。后端由 omlx 或其他 OpenAI-compatible server 独立安装和管理。

```bash
cd ~/workspace/kiln
./install.sh
```

安装脚本只会把 `kiln` 链接到 `~/.local/bin/kiln`，不会修改或启动后端。

## 环境变量

所有配置都通过环境变量完成，环境变量优先于 CLI 内置默认值：

```zsh
export KILN_BASE_URL=http://127.0.0.1:8007
export KILN_API_KEY=local

export KILN_MODEL=ornith-ai--Ornith-1.5-35B-A3B-MLX-4bit
export KILN_OCR_MODEL=Unlimited-OCR-mxfp8
export KILN_EMBEDDING_MODEL=mlx-community--Qwen3-Embedding-4B-4bit-DWQ
export KILN_TRANSLATE_MODEL=Hy-MT2-1.8B-4bit
```

本地后端只要检查 Authorization header，`KILN_API_KEY` 可以是任意非空值。也可以不设置它，CLI 会使用 `local`；如果设置了 `KILN_API_KEY_FILE`，CLI 会从该文件读取 key。

模型 fallback 规则：

| 能力 | 环境变量 | 未设置时 |
| --- | --- | --- |
| Chat | `KILN_MODEL` | 使用 CLI 默认模型 |
| OCR | `KILN_OCR_MODEL` | fallback 到 `KILN_MODEL` |
| Translate | `KILN_TRANSLATE_MODEL` | fallback 到 `KILN_MODEL` |
| Embedding | `KILN_EMBEDDING_MODEL` | 不可用，直接报错 |

## 命令

```bash
kiln doctor
kiln models
kiln chat '解释一下什么是 RAG'
printf '%s\n' '总结这段文本' | kiln chat
kiln translate --lang 中文 'Hello, world.'
kiln embed '这段文字用于向量检索'
kiln ocr ./invoice.png

OCR 也可以接收自定义指令或 HTTP(S) 图片 URL：

```bash
kiln ocr '只输出图片中的文字' ./invoice.png
kiln ocr https://example.com/image.png
```

### Chat

`kiln chat` 使用 `/v1/chat/completions` 和 `KILN_MODEL`，不带参数时从 stdin 读取。长文本通过 stdin 传入，不受 shell 参数长度限制。

### Translate

`kiln translate` 使用 `/v1/chat/completions` 和 `KILN_TRANSLATE_MODEL`。默认目标语言是英文，可用 `--lang` 或 `-l` 指定目标语言：

```bash
kiln translate '今天天气不错。'
kiln translate --lang 中文 'The weather is nice today.'
```

CLI 会附加“只输出译文”的提示，避免翻译模型退化成普通聊天。也可以用 `KILN_TRANSLATE_INSTRUCTION` 完全覆盖默认提示。

### Embedding

`kiln embed` 使用 `/v1/embeddings`。必须设置 `KILN_EMBEDDING_MODEL`，输出原始 OpenAI-compatible JSON，适合继续被脚本解析。

### OCR

`kiln ocr` 使用 `/v1/chat/completions`，把本地图片编码成 data URL，或直接传递 HTTP(S) 图片 URL。默认附加 OCR 指令：`请识别图片中的全部文字并原样输出`。可用 `KILN_OCR_INSTRUCTION` 覆盖，也可以把自定义指令作为第一个参数传入。

当前 OCR 接受图片，不直接接受 PDF、DOCX 等文档容器。它打印 OCR 模型返回的文本，不再生成 Markdown、JSON、DOCX 或 layout PNG。

### Doctor 和 Models

```bash
kiln doctor
kiln models
```

`doctor` 请求 `/health` 并打印后端返回的 JSON；`models` 请求 `/v1/models`，每行打印一个模型 id。

### 日志

日志不是 Kiln 管理的。若后端写入了本地日志，可以显式设置 `KILN_LOG` 后使用：

```bash
KILN_LOG=/path/to/backend.log kiln logs -f
```

## API

CLI 使用的 endpoint：

| 命令 | Endpoint |
| --- | --- |
| `chat` / `translate` / `ocr` | `/v1/chat/completions` |
| `embed` | `/v1/embeddings` |
| `models` | `/v1/models` |
| `doctor` | `/health` |

模型切换期间后端可能暂时拒绝连接。CLI 默认重试 12 次，每次间隔 3 秒，可用 `KILN_RETRIES` 和 `KILN_RETRY_DELAY` 调整。

## 文件

| 文件 | 用途 |
| --- | --- |
| `kiln` | 纯 OpenAI-compatible CLI |
| `install.sh` | 安装 CLI 软链接，不管理后端 |
| `verify.sh` | 针对运行中 API 的 CLI 回归检查 |
| `bench.py` | OpenAI-compatible API 基准脚本 |
| `kiln_server.py` / `kiln_config.py` | 旧版后端实现，CLI 不再调用 |

API key、模型缓存和 OCR 输出不要提交到仓库。
