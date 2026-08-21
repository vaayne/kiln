# Kiln CLI 约定

Kiln 是纯 OpenAI-compatible CLI。后端由 omlx 或其他兼容服务独立运行，CLI 不启动、停止、重启、配置或监督后端。

## 架构

- 默认 API：`http://127.0.0.1:8007`
- Chat：`/v1/chat/completions`，模型来自 `KILN_MODEL`
- OCR：同一 chat endpoint，模型来自 `KILN_OCR_MODEL`，未设置时 fallback 到 `KILN_MODEL`
- Translate：同一 chat endpoint，模型来自 `KILN_TRANSLATE_MODEL`，未设置时 fallback 到 `KILN_MODEL`
- Embedding：`/v1/embeddings`，必须设置 `KILN_EMBEDDING_MODEL`

配置只来自环境变量，不再使用 `config.sh`、TOML、launchd 或 PaddleOCR。

## 不要做

不要把后端启动、模型加载、launchd 生命周期、运行参数配置或 OCR 版面解析重新放回 CLI。OCR 只负责把图片发给配置的 OCR 模型并打印返回值；PDF 和 office 容器由调用方先转换为图片。

不要读取、打印或提交 API key。`KILN_API_KEY` 在本地可以是任意非空值；也支持 `KILN_API_KEY_FILE`。

## 验证

改动后运行 `./verify.sh`。它覆盖 CLI 语法、health、模型列表、chat、translate、embedding、OCR 和错误路径。不要只检查进程是否存在。

模型切换期间后端可能暂时拒绝连接，CLI 默认重试 12 次、每次间隔 3 秒；直接调用 API 的客户端需要自行处理重试。

## 安全

API key、模型缓存和 OCR 输出不要提交到仓库。