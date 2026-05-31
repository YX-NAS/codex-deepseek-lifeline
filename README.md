# Codex DeepSeek Lifeline

Local DeepSeek proxy for Codex Desktop / Codex CLI.

一个给 Codex Desktop / Codex CLI 使用的本地 DeepSeek 代理。

Current stable version / 当前稳定版本：`1.1.2`

This repository is also packaged as a Codex plugin.

这个仓库现在也可以作为 Codex 插件使用。

## Languages

- [简体中文](README.zh-CN.md)
- [English](README.en.md)

## Quick Start

```bash
git clone https://github.com/YX-NAS/codex-deepseek-lifeline.git
cd codex-deepseek-lifeline
bash scripts/install.sh
~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro
```

The switch command prompts for your DeepSeek API key, updates Codex config, starts the local proxy, and writes logs to `~/.codex/deepseek-proxy.log`.

一键切换命令会提示输入 DeepSeek API Key，自动更新 Codex 配置、启动本地代理，并把日志写入 `~/.codex/deepseek-proxy.log`。

After turning it on, fully quit and reopen Codex Desktop.

开启后请完全退出并重新打开 Codex Desktop。

## Common Commands

```bash
# Status / 查看状态
~/.codex/codex-deepseek-switch.sh status

# Turn off / 关闭并恢复
~/.codex/codex-deepseek-switch.sh off
```

## Defaults

- Default model / 默认模型：`deepseek-v4-flash`
- Recommended model / 推荐模型：`deepseek-v4-pro`
- Local proxy / 本地代理：`http://127.0.0.1:4446/v1`
- Thinking mode / Thinking 模式：`disabled`

See the full documentation:

- [README.zh-CN.md](README.zh-CN.md)
- [README.en.md](README.en.md)
