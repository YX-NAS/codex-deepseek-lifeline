# Codex DeepSeek Lifeline

Emergency fallback for Codex CLI/Desktop when your OpenAI/Codex quota is temporarily unavailable.

It runs a local proxy that accepts Codex-style Responses API requests and forwards them to a DeepSeek-compatible Chat Completions endpoint. The goal is not to fully replace Codex's official models. It is a temporary "keep working" mode for ordinary chat and lightweight coding tasks.

## What This Does

- Adds a `deepseek` Codex profile at `~/.codex/deepseek.config.toml`.
- Installs a local proxy at `~/.codex/codex-deepseek-proxy.js`.
- Adds helper scripts to start the proxy, run `codex exec` with DeepSeek, and temporarily switch Codex Desktop.
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

Start the proxy first:

```bash
export CODEX_DEEPSEEK_KEY="your-new-deepseek-key"
~/.codex/start-deepseek-proxy.sh
```

Switch Codex Desktop to the fallback config:

```bash
~/.codex/codex-deepseek-on.sh
```

Then fully quit and reopen Codex Desktop.

Restore the normal config:

```bash
~/.codex/codex-deepseek-off.sh
```

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
