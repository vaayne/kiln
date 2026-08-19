# Local MLX 运行约定

Apple Silicon 上的本地 AI 能力包。安装、命令和 endpoint 见 `README.md`，这里只写改动它时必须知道的约束。

## 架构不变量

只有一个 `mlx_vlm.server` 进程，由 launchd 管理，label `local.kiln.server`，入口是 `kiln serve`。Agent 的 Qwen 启动时预加载；Embedding 和 OCR 靠请求里的模型名按需加载。同一时刻只有一个生成模型常驻。

切换生成模型时 server 会重建 worker，约 10~15 秒内连接被拒。`kiln` 各命令统一重试 12 次 x 3 秒，直接调 HTTP API 的客户端也必须自己重试。

完整 OCR 不直接请求 VLM。PaddleOCR 在 CPU 上负责版面检测、阅读顺序和结果保存，MLX-VLM 只作为识别后端，这是 PaddleOCR 官方的 Apple Silicon 集成方式。

端口、模型名和路径只在 `config.sh` 定义一次，`install.sh`、`kiln`、`verify.sh` 都从那里读。server 的启动参数在 `kiln serve` 里，launchd 直接调它。不要在任何地方硬编码，两边一旦不一致，server 会静默卸载预加载模型再重载另一个，只表现为"变慢"。

## 不要做

不要把 PaddleOCR 依赖装进 MLX-VLM 的 uv tool，也不要把 `jinja2` 装进系统 Python。两套依赖必须隔离，PaddleOCR 用 `.venv-paddleocr` 的 Python 3.12。

`uv tool install` 必须带 `--with jinja2`，它是 chat template 的运行时依赖，漏了会在重启后让所有 chat 请求返回 500。

`--thinking-budget` 不能与 MTP speculative decoding 同用，server 会直接报错。

`--draft-block-size` 不要改成 4，实测解码速度明显下降；2 没有收益。当前值 3。

`max-kv-size=65536` 是硬上限，模型原生上下文约 256K。超过 64K 会 rotating KV 静默覆盖旧上下文，不报错，不能当无限上下文用。

## 验证

改完跑 `./verify.sh`，它覆盖 chat、embedding、OCR 四类产物、模型切换恢复和错误路径，全绿才算完。不要只看进程是否存在。`doctor` 会打印服务实际加载了哪些模型分组，排查内存和模型切换问题先看它。

Agent 短 prompt 基线约 25 tok/s，4.8K prompt 约 22~24 tok/s。比较参数前冷却约 3 分钟并用相同请求，否则会被日常应用内存占用和积热干扰。

OCR 回归要看四类产物齐全：Markdown、JSON、DOCX、layout PNG。

## 安全

`api-key` 是密钥，已被 `.gitignore` 排除。不要读取后写入文档、日志、提交或回复。模型缓存和 OCR 输出也不提交。
