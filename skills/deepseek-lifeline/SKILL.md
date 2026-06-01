---
name: deepseek-lifeline
description: Install, enable, disable, inspect, or troubleshoot Codex DeepSeek Lifeline, the local DeepSeek proxy for Codex Desktop and Codex CLI. Use when the user asks to switch Codex to DeepSeek, check whether DeepSeek is active, restore official Codex settings, update the proxy scripts, or diagnose DeepSeek tool-call/model issues.
---

# Codex DeepSeek Lifeline

Use this skill when the user wants to operate the Codex DeepSeek Lifeline plugin or its installed helper scripts.

## What This Plugin Does

- Installs a local proxy at `~/.codex/codex-deepseek-proxy.js`.
- Installs a one-command switch at `~/.codex/codex-deepseek-switch.sh`.
- Switches Codex Desktop to a local DeepSeek-compatible provider by editing `~/.codex/config.toml`.
- Stores the DeepSeek API key in the macOS launch environment with `launchctl setenv CODEX_DEEPSEEK_KEY ...`.
- Starts or restarts the local proxy on `127.0.0.1:4446`.
- Writes proxy logs to `~/.codex/deepseek-proxy.log`.
- Writes usage and cost-estimate records to `~/.codex/deepseek-usage.jsonl`.

Never ask the user to put their API key in source code, README files, Git commits, or project config files.

## Default Models

- Default fast model: `deepseek-v4-flash`
- Recommended high-capability model: `deepseek-v4-pro`
- Default thinking mode: `CODEX_DEEPSEEK_THINKING=disabled`
- Default billing currency: `CODEX_DEEPSEEK_BILLING_CURRENCY=auto`

Thinking mode is disabled by default because the proxy does not preserve DeepSeek `reasoning_content` across Codex tool-call turns. Keeping thinking disabled makes Codex tool calls more stable.

## Install Or Update

From the repository root:

```bash
bash scripts/install.sh
```

This copies the proxy and helper scripts into `~/.codex`. It does not store the API key.

## Enable DeepSeek

Use the one-command switch:

```bash
~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro
```

If the user does not specify a model, use:

```bash
~/.codex/codex-deepseek-switch.sh on
```

The script prompts for the DeepSeek API key if it is not already available from the current shell or macOS launch environment. After enabling, tell the user to fully quit and reopen Codex Desktop.

## Check Status

```bash
~/.codex/codex-deepseek-switch.sh status
```

A healthy state should show:

```text
model_provider = "openai"
base_url = "http://127.0.0.1:4446/v1"
node ... 127.0.0.1:4446 (LISTEN)
CODEX_DEEPSEEK_THINKING=disabled
CODEX_DEEPSEEK_KEY=(set)
```

The active model is shown in `~/.codex/config.toml`, `CODEX_MODEL`, and the proxy log.

DeepSeek mode intentionally reuses the `openai` provider name so Codex Desktop keeps showing existing OpenAI-provider project conversations. The local proxy still routes requests to DeepSeek.

## View Logs

```bash
tail -f ~/.codex/deepseek-proxy.log
```

Real requests look like:

```text
target=https://api.deepseek.com model=deepseek-v4-pro thinking=disabled
-> /v1/responses -> https://api.deepseek.com/v1/chat/completions [deepseek-v4-pro]
```

## Visual UI

Use the terminal menu:

```bash
~/.codex/codex-deepseek-switch.sh ui
```

Start the local dashboard:

```bash
~/.codex/codex-deepseek-dashboard.sh
```

The dashboard is local-only by default at `http://127.0.0.1:4456`. It can show status, usage, recent logs, and common commands. It may switch models or turn DeepSeek off when `CODEX_DEEPSEEK_KEY` is already available in the macOS launch environment, but it must not ask the user to type an API key into the browser.

## Model Catalog

List built-in and custom models:

```bash
~/.codex/codex-deepseek-switch.sh models
```

Built-in models are `deepseek-v4-flash`, `deepseek-v4-pro`, `deepseek-chat`, and `deepseek-reasoner`. Custom OpenAI-compatible models are read from `~/.codex/deepseek-models.custom.json`. If custom model JSON is invalid, report the warning but continue using built-in models. Unknown or unpriced models may still run, but cost estimates must be described as `n/a`.

## Estimate Cost

Use:

```bash
~/.codex/codex-deepseek-switch.sh cost
```

Other views:

```bash
~/.codex/codex-deepseek-switch.sh cost today
~/.codex/codex-deepseek-switch.sh cost all
~/.codex/codex-deepseek-switch.sh cost tail
```

The proxy writes one JSONL record per successful upstream response to `~/.codex/deepseek-usage.jsonl`. The estimate uses DeepSeek official V4 prices per 1M tokens in the selected billing currency.

CNY billing:

- `deepseek-v4-flash`: cache-hit input `¥0.02`, cache-miss input `¥1`, output `¥2`.
- `deepseek-v4-pro`: cache-hit input `¥0.025`, cache-miss input `¥3`, output `¥6`.

USD billing:

- `deepseek-v4-flash`: cache-hit input `$0.0028`, cache-miss input `$0.14`, output `$0.28`.
- `deepseek-v4-pro`: cache-hit input `$0.003625`, cache-miss input `$0.435`, output `$0.87`.

If DeepSeek does not return explicit cache-miss tokens, the proxy estimates cache miss as total input minus cache-hit input. `CODEX_DEEPSEEK_BILLING_CURRENCY=auto` chooses CNY for Chinese/China environments and USD otherwise. Always describe this as an estimate and tell the user to verify final charges in the DeepSeek billing console.

## Disable DeepSeek

```bash
~/.codex/codex-deepseek-switch.sh off
```

This stops the local proxy, restores the previous `~/.codex/config.toml` backup when available, and clears related macOS launch environment variables. After disabling, tell the user to fully quit and reopen Codex Desktop.

Always use `~/.codex/codex-deepseek-switch.sh off` for disable requests. Do not use the legacy `codex-deepseek-off.sh` helper directly, and do not manually kill proxy PIDs unless the switch command fails and status still shows a listener on port `4446`.

After running the off command, verify with:

```bash
~/.codex/codex-deepseek-switch.sh status
```

The expected disabled state is:

```text
No proxy listening on 127.0.0.1:4446
CODEX_MODEL=
CODEX_DEEPSEEK_KEY=(not set)
```

## Troubleshooting

- `Missing environment variable: CODEX_DEEPSEEK_KEY`: run `~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro` so the script can prompt for the key and write it to the macOS launch environment.
- `EADDRINUSE 127.0.0.1:4446`: run the switch command again; it stops the old proxy before starting a new one.
- Tool calls appear as plain text: update/reinstall the proxy so text-tool-call recovery is available, confirm `CODEX_DEEPSEEK_THINKING=disabled` in `status`, then restart Codex Desktop.
- Disable command appears as `Tool call exec_command ...` text instead of executing: tell the user this means the current model response did not actually execute tools, then run `~/.codex/codex-deepseek-switch.sh off` from a tool-capable session or ask the user to paste that command into Terminal.
- Cost shows no data: make sure at least one request has gone through the proxy after upgrading to the cost-estimate version, then check `~/.codex/deepseek-usage.jsonl`.
- `rg: command not found`: use `grep -nE` for shell checks on machines without ripgrep.

## Safety

If the user pasted an API key into chat, logs, public repos, or screenshots, advise them to revoke it in the DeepSeek console and create a fresh key.
