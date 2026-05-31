# Codex DeepSeek Lifeline

> 中文说明在前，English follows below.

## 中文说明

Codex DeepSeek Lifeline 是一个给 Codex CLI / Codex Desktop 准备的临时续命方案。当 OpenAI / Codex 额度暂时不可用时，它可以把 Codex 的模型请求转发到 DeepSeek 或其他 OpenAI-compatible Chat Completions 服务。

它不是官方 DeepSeek 集成，也不是要完全替代 Codex 官方模型。更准确地说，它是一个本机代理：接收 Codex 风格的 Responses API 请求，再转换成 DeepSeek 支持的 Chat Completions 请求。适合普通问答、代码解释、轻量代码修改；不建议用于复杂长任务、图片输入、web search 或高可靠自动化。

### 它会做什么

- 在 `~/.codex/deepseek.config.toml` 添加一个 `deepseek` 备用 profile。
- 在 `~/.codex/codex-deepseek-proxy.js` 安装本地代理。
- 添加几个辅助脚本，用于一键切换、启动代理、CLI 续命、桌面端临时切换和恢复。
- 从环境变量 `CODEX_DEEPSEEK_KEY` 读取 DeepSeek API Key。
- 不会把你的 API Key 写入磁盘。

### 安装

```bash
git clone https://github.com/YX-NAS/codex-deepseek-lifeline.git
cd codex-deepseek-lifeline
bash scripts/install.sh
```

### CLI 续命用法

打开第一个终端，启动本地代理：

```bash
export CODEX_DEEPSEEK_KEY="你的新 DeepSeek Key"
~/.codex/start-deepseek-proxy.sh
```

打开第二个终端，通过 DeepSeek profile 运行 Codex：

```bash
~/.codex/codex-deepseek-exec.sh exec "解释一下这个项目"
```

### Codex Desktop 续命用法

推荐使用一键切换。它会提示输入 API Key、写入 Codex Desktop 可读取的 macOS 环境变量、切换配置、重启本地代理：

```bash
~/.codex/codex-deepseek-switch.sh on deepseek-reasoner
```

如果不指定模型，默认使用 `deepseek-chat`：

```bash
~/.codex/codex-deepseek-switch.sh on
```

然后完全退出并重新打开 Codex Desktop。

查看当前状态：

```bash
~/.codex/codex-deepseek-switch.sh status
```

验证成功时应重点看到：

```text
model_provider = "deepseek_proxy"
model = "deepseek-reasoner"
base_url = "http://127.0.0.1:4446/v1"
node ... 127.0.0.1:4446 (LISTEN)
CODEX_MODEL=deepseek-reasoner
CODEX_DEEPSEEK_KEY=(set)
```

其中 `~/.codex/config.toml` 是 Codex Desktop 当前默认生效配置；`~/.codex/deepseek.config.toml` 是备用 profile，默认仍可能显示 `deepseek-chat`，这不影响全局切换后的实际模型。

恢复官方默认配置：

```bash
~/.codex/codex-deepseek-switch.sh off
```

兼容旧命令：`~/.codex/codex-deepseek-on.sh` 等同于 `switch.sh on`，`~/.codex/codex-deepseek-off.sh` 等同于 `switch.sh off`。

### 配置项

默认值：

```bash
CODEX_PROXY_TARGET=https://api.deepseek.com
CODEX_MODEL=deepseek-chat
CODEX_DEEPSEEK_PROXY_HOST=127.0.0.1
CODEX_DEEPSEEK_PROXY_PORT=4446
CODEX_PROXY_MAX_CONCURRENT=1
```

如果你使用其他 OpenAI-compatible 服务，可以这样改：

```bash
export CODEX_PROXY_TARGET="https://your-compatible-endpoint.example"
export CODEX_MODEL="your-model-name"
```

### 限制

- 工具调用是尽力兼容，复杂 schema 可能失败。
- 图片输入会被丢弃，因为这里使用的 DeepSeek chat 模型不支持 Codex 的图片 payload。
- Web search、长时间 agentic 任务、多工具复杂工作流，稳定性通常不如 Codex 官方模型。
- Codex Desktop 的某些能力可能仍然依赖 OpenAI / ChatGPT 账户服务，不能只靠代理完全替代。

### 安全建议

建议使用新的、权限尽量小的 API Key，并且只通过环境变量传入。不要把 Key 写进 README、脚本、配置文件、Git 提交或聊天记录里。测试结束后可以考虑轮换或删除临时 Key。

本地代理默认只监听 `127.0.0.1`。除非你非常清楚风险，否则不要把监听地址改成 `0.0.0.0`。

### 卸载

```bash
bash scripts/uninstall.sh
```

如果桌面端曾经切到 DeepSeek fallback，卸载脚本会尽量恢复之前备份的 `~/.codex/config.toml`。

---

## English

Emergency fallback for Codex CLI/Desktop when your OpenAI/Codex quota is temporarily unavailable.

It runs a local proxy that accepts Codex-style Responses API requests and forwards them to a DeepSeek-compatible Chat Completions endpoint. The goal is not to fully replace Codex's official models. It is a temporary "keep working" mode for ordinary chat and lightweight coding tasks.

## What This Does

- Adds a `deepseek` Codex profile at `~/.codex/deepseek.config.toml`.
- Installs a local proxy at `~/.codex/codex-deepseek-proxy.js`.
- Adds helper scripts to one-command switch, start the proxy, run `codex exec` with DeepSeek, and temporarily switch Codex Desktop.
- Reads your DeepSeek API key from `CODEX_DEEPSEEK_KEY`.
- Never writes your API key to disk.

## Install

```bash
git clone https://github.com/YX-NAS/codex-deepseek-lifeline.git
cd codex-deepseek-lifeline
bash scripts/install.sh
```

## CLI Fallback

Terminal 1:

```bash
export CODEX_DEEPSEEK_KEY="your-new-deepseek-key"
~/.codex/start-deepseek-proxy.sh
```

Terminal 2:

```bash
~/.codex/codex-deepseek-exec.sh exec "Explain this project"
```

## Desktop Fallback

Use the one-command switch. It prompts for your API key, sets the macOS environment variables Codex Desktop can read, switches the config, and restarts the local proxy:

```bash
~/.codex/codex-deepseek-switch.sh on deepseek-reasoner
```

If you omit the model, it defaults to `deepseek-chat`:

```bash
~/.codex/codex-deepseek-switch.sh on
```

Then fully quit and reopen Codex Desktop.

Check status:

```bash
~/.codex/codex-deepseek-switch.sh status
```

A successful switch should show the important lines below:

```text
model_provider = "deepseek_proxy"
model = "deepseek-reasoner"
base_url = "http://127.0.0.1:4446/v1"
node ... 127.0.0.1:4446 (LISTEN)
CODEX_MODEL=deepseek-reasoner
CODEX_DEEPSEEK_KEY=(set)
```

`~/.codex/config.toml` is the active Codex Desktop default config. `~/.codex/deepseek.config.toml` is only the fallback profile and may still show `deepseek-chat`; that does not override the global switch.

Restore the normal config:

```bash
~/.codex/codex-deepseek-switch.sh off
```

Legacy shortcuts still work: `~/.codex/codex-deepseek-on.sh` delegates to `switch.sh on`, and `~/.codex/codex-deepseek-off.sh` delegates to `switch.sh off`.

## Configuration

Defaults:

```bash
CODEX_PROXY_TARGET=https://api.deepseek.com
CODEX_MODEL=deepseek-chat
CODEX_DEEPSEEK_PROXY_HOST=127.0.0.1
CODEX_DEEPSEEK_PROXY_PORT=4446
CODEX_PROXY_MAX_CONCURRENT=1
```

You can use another OpenAI-compatible endpoint:

```bash
export CODEX_PROXY_TARGET="https://your-compatible-endpoint.example"
export CODEX_MODEL="your-model-name"
```

## Limitations

- Tool calls are best-effort and may fail on complex schemas.
- Image input is dropped because DeepSeek chat models do not support Codex image payloads here.
- Web search, long-running agentic tasks, and complex multi-tool workflows are less reliable than official Codex models.
- Some Codex Desktop features may still require OpenAI/ChatGPT account services.

## Safety

Use a fresh, limited API key and keep it in an environment variable. Do not paste keys into chat logs, README files, scripts, or shell history if you can avoid it.

## Uninstall

```bash
bash scripts/uninstall.sh
```
