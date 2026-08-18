# mlx-vlm 运行约定

## 安装与升级

使用 uv tool 安装时必须显式带上 `jinja2`。`transformers` 的 chat template 运行时需要它，而 `mlx-vlm` 的依赖树不一定会自动安装。

```bash
uv tool install --force --with jinja2 mlx-vlm@latest
```

不要把 `jinja2` 安装到系统 Python。服务使用的是：

```text
~/.local/share/uv/tools/mlx-vlm/bin/python
```

## 当前服务配置

服务脚本：`start-qwen38-mtp.sh`

```text
model:           mlx-community/Qwen3.8-27B-4bit
draft-model:    mlx-community/Qwen3.8-27B-MTP-4bit
draft-kind:     mtp
draft-block:    3
kv-bits:        8
quantized-start:2048
max-kv-size:    65536
max-num-seqs:   1
prefill-step:   2048
max-tokens:     16384
thinking:       enabled
```

这些参数针对 48GB M5 Pro MacBook Pro 的单人日常使用调过。`draft-block-size` 不要随意改成 4，实测解码速度明显下降；2 也没有收益。

`--thinking-budget` 不可与 speculative decoding/MTP 同时使用，服务端会报错，因此不要加到启动参数中。

## 重启与验证

服务由 launchd 管理，Label 是 `local.mlx-vlm.qwen38-mtp`：

```bash
launchctl kickstart -k gui/$(id -u)/local.mlx-vlm.qwen38-mtp
python3 ~/.config/mlx-vlm/bench.py
```

服务地址是 `http://127.0.0.1:8007`。日志：

```text
~/Library/Logs/mlx-vlm-qwen38-mtp.log
~/Library/Logs/mlx-vlm-qwen38-mtp.error.log
```

## 性能基线

当前配置在短 prompt 下约 `25 tok/s`，4.8k prompt 下解码约 `22~24 tok/s`。连续压测会受到日常应用内存占用和积热影响，比较参数时应先冷却约 3 分钟，并使用相同请求。

## 上下文限制

模型原生上下文是 256K。当前 `max-kv-size=65536`，64K 以内完整保留；超过上限会使用 rotating KV cache 静默覆盖旧上下文，不会返回错误。不要在不确认语义损失的情况下把它当作无限上下文使用。

## 安全

`api-key` 是密钥，不要读取后写入文档、日志、提交或回复中。
