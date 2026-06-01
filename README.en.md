# Codex DeepSeek Lifeline

Codex DeepSeek Lifeline is a local DeepSeek proxy for Codex Desktop and Codex CLI. It translates Codex-style Responses API requests into DeepSeek-compatible Chat Completions requests, so you can keep working when your official Codex quota is unavailable or when you want to temporarily use DeepSeek.

Current stable version: `1.2.1`

Starting with `1.1.0`, this project is packaged as a Codex plugin with `.codex-plugin/plugin.json` and the `deepseek-lifeline` skill.

The current main entry point is the one-command switch:

```bash
~/.codex/codex-deepseek-switch.sh
```

It handles config switching, API key environment setup, local proxy restart, and status checks. Normal use does not require multiple terminals, and you should not put your API key in source code or config files.

## Current Defaults

- Default model: `deepseek-v4-flash`
- Recommended higher-capability model: `deepseek-v4-pro`
- Default endpoint: `https://api.deepseek.com`
- Local proxy: `http://127.0.0.1:4446/v1`
- Default thinking mode: `disabled`
- Default billing currency: `auto`, which uses `CNY` for Chinese/China environments and `USD` otherwise
- API key env var: `CODEX_DEEPSEEK_KEY`

DeepSeek V4 models support thinking mode by default, but Codex tool calls need stable context conversion. This proxy disables thinking by default:

```bash
CODEX_DEEPSEEK_THINKING=disabled
```

This reduces cases where tool calls are emitted as plain text instead of being executed by Codex.

## Install

```bash
git clone https://github.com/YX-NAS/codex-deepseek-lifeline.git
cd codex-deepseek-lifeline
bash scripts/install.sh
```

The installer writes these files to `~/.codex`:

```text
~/.codex/codex-deepseek-proxy.js
~/.codex/codex-deepseek-switch.sh
~/.codex/codex-deepseek-on.sh
~/.codex/codex-deepseek-off.sh
~/.codex/start-deepseek-proxy.sh
~/.codex/deepseek.config.toml
```

The installer does not store your API key.

## Use As A Codex Plugin

This repository includes a plugin manifest:

```text
.codex-plugin/plugin.json
skills/deepseek-lifeline/SKILL.md
```

After installing it as a Codex plugin, you can ask Codex:

```text
Enable DeepSeek Lifeline with deepseek-v4-pro
```

Or:

```text
Check DeepSeek Lifeline status
```

The plugin skill guides Codex through installation, enabling, disabling, status checks, and troubleshooting. The actual one-command switch remains `~/.codex/codex-deepseek-switch.sh`.

## Turn On

Recommended model:

```bash
~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro
```

The script prompts:

```text
DeepSeek API Key:
```

Paste your DeepSeek API key and press Enter. The key is not echoed to the terminal.

If you omit the model, it uses `deepseek-v4-flash`:

```bash
~/.codex/codex-deepseek-switch.sh on
```

The switch command automatically:

- Sets `CODEX_DEEPSEEK_KEY` in the macOS launch environment so Codex Desktop can read it.
- Sets `CODEX_MODEL`.
- Sets `CODEX_PROXY_TARGET`.
- Sets `CODEX_DEEPSEEK_THINKING=disabled`.
- Updates `~/.codex/config.toml` to point Codex at the local DeepSeek proxy.
- Stops any old proxy process on port `4446`.
- Starts a new local proxy in the background.
- Uses a macOS LaunchAgent to keep the proxy process stable.
- Writes proxy logs to `~/.codex/deepseek-proxy.log`.
- Writes token usage and cost-estimate records to `~/.codex/deepseek-usage.jsonl`.

After turning it on, fully quit and reopen Codex Desktop. Starting a new chat alone may not reload the config.

## Check Status

```bash
~/.codex/codex-deepseek-switch.sh status
```

A successful switch should show the key lines below:

```text
model_provider = "openai"
model = "deepseek-v4-pro"
base_url = "http://127.0.0.1:4446/v1"
node ... 127.0.0.1:4446 (LISTEN)
CODEX_MODEL=deepseek-v4-pro
CODEX_DEEPSEEK_THINKING=disabled
CODEX_DEEPSEEK_KEY=(set)
```

Notes:

- `~/.codex/config.toml` is the active default config for Codex Desktop.
- `~/.codex/deepseek.config.toml` is a fallback profile and may still show `deepseek-v4-flash`.
- The actual request model is determined by `config.toml`, `CODEX_MODEL`, and the proxy log.
- To keep existing Codex Desktop project conversations visible, DeepSeek mode reuses the `openai` provider name while temporarily routing it to the local proxy; `off` restores the original config.

View the proxy log:

```bash
tail -f ~/.codex/deepseek-proxy.log
```

When real requests arrive, you should see lines like:

```text
target=https://api.deepseek.com model=deepseek-v4-pro thinking=disabled
-> /v1/responses -> https://api.deepseek.com/v1/chat/completions [deepseek-v4-pro]
```

## Cost Estimate

Show total and today's estimate:

```bash
~/.codex/codex-deepseek-switch.sh cost
```

Show today only:

```bash
~/.codex/codex-deepseek-switch.sh cost today
```

Show the last 10 raw records:

```bash
~/.codex/codex-deepseek-switch.sh cost tail
```

The proxy records DeepSeek usage results in `~/.codex/deepseek-usage.jsonl`. Built-in official V4 prices, per 1M tokens:

CNY billing:

| Model | Cache-hit input | Cache-miss input | Output |
| --- | ---: | ---: | ---: |
| `deepseek-v4-flash` | `¥0.02` | `¥1` | `¥2` |
| `deepseek-v4-pro` | `¥0.025` | `¥3` | `¥6` |

USD billing:

| Model | Cache-hit input | Cache-miss input | Output |
| --- | ---: | ---: | ---: |
| `deepseek-v4-flash` | `$0.0028` | `$0.14` | `$0.28` |
| `deepseek-v4-pro` | `$0.003625` | `$0.435` | `$0.87` |

If DeepSeek does not return explicit cache-miss tokens, the proxy estimates cache miss as `input_tokens - cache_hit_tokens`. This feature is only an estimate; verify final charges in the DeepSeek billing console.

By default, `CODEX_DEEPSEEK_BILLING_CURRENCY=auto` selects the display currency from the local environment. You can force one:

```bash
export CODEX_DEEPSEEK_BILLING_CURRENCY=CNY
~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro
```

## Turn Off

```bash
~/.codex/codex-deepseek-switch.sh off
```

It will:

- Stop the local proxy.
- Restore the previous `~/.codex/config.toml` backup.
- Clear `CODEX_DEEPSEEK_KEY`, `CODEX_MODEL`, `CODEX_PROXY_TARGET`, and `CODEX_DEEPSEEK_THINKING` from the macOS launch environment.

After turning it off, fully quit and reopen Codex Desktop.

If Codex shows `Tool call exec_command ...` as plain text instead of actually turning the proxy off, the current model emitted a tool call as text. Run the `off` command directly in Terminal.

## Common Commands

```bash
# Turn on the higher-capability model
~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro

# Turn on the default faster model
~/.codex/codex-deepseek-switch.sh on

# Check status
~/.codex/codex-deepseek-switch.sh status

# List available models
~/.codex/codex-deepseek-switch.sh models

# Turn off
~/.codex/codex-deepseek-switch.sh off

# Watch logs
tail -f ~/.codex/deepseek-proxy.log

# Show cost estimate
~/.codex/codex-deepseek-switch.sh cost

# Open terminal menu
~/.codex/codex-deepseek-switch.sh ui

# Start the local Web dashboard
~/.codex/codex-deepseek-dashboard.sh
```

Legacy commands still work:

```bash
~/.codex/codex-deepseek-on.sh
~/.codex/codex-deepseek-off.sh
```

They delegate to `codex-deepseek-switch.sh`.

## Visual Dashboard

`v1.3.0` adds two local visual entry points:

```bash
~/.codex/codex-deepseek-switch.sh ui
```

The terminal menu can show status, start the default model, start `deepseek-v4-pro`, turn DeepSeek off, show cost, show recent logs, and open the Web dashboard.

```bash
~/.codex/codex-deepseek-dashboard.sh
```

The Web dashboard listens on:

```text
http://127.0.0.1:4456
```

It shows proxy status, current model, target URL, thinking mode, usage summary, recent logs, and common commands. It can refresh status, switch models, and turn the proxy off, but it never accepts or stores API keys in the browser. If the desktop environment does not have a key, run `~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro` in Terminal.

## Model Catalog and Custom Models

`v1.4.0` includes a built-in DeepSeek model catalog:

- `deepseek-v4-flash`
- `deepseek-v4-pro`
- `deepseek-chat`
- `deepseek-reasoner`

List models:

```bash
~/.codex/codex-deepseek-switch.sh models
```

`status` shows the active model display name, provider, target URL, source, and whether pricing is available. Models without pricing can still run, but cost estimates show `n/a`.

Custom OpenAI-compatible models live at:

```text
~/.codex/deepseek-models.custom.json
```

Example:

```json
{
  "models": [
    {
      "id": "my-compatible-model",
      "displayName": "My Compatible Model",
      "provider": "Custom",
      "targetBase": "https://api.example.com",
      "billingCurrency": "USD",
      "pricesPer1M": {
        "USD": {
          "inputCacheHit": 0,
          "inputCacheMiss": 0.2,
          "output": 0.6
        }
      },
      "notes": "OpenAI-compatible Chat Completions endpoint"
    }
  ]
}
```

The Web dashboard can also list catalog models and save custom model JSON. If the custom JSON is invalid, built-in models remain available.

## Configuration

Defaults:

```bash
CODEX_PROXY_TARGET=https://api.deepseek.com
CODEX_MODEL=deepseek-v4-flash
CODEX_DEEPSEEK_THINKING=disabled
CODEX_DEEPSEEK_BILLING_CURRENCY=auto
CODEX_DEEPSEEK_PROXY_HOST=127.0.0.1
CODEX_DEEPSEEK_PROXY_PORT=4446
CODEX_DEEPSEEK_DASHBOARD_HOST=127.0.0.1
CODEX_DEEPSEEK_DASHBOARD_PORT=4456
CODEX_PROXY_MAX_CONCURRENT=1
```

Temporarily choose a model:

```bash
~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro
```

Use another OpenAI-compatible endpoint:

```bash
export CODEX_PROXY_TARGET="https://your-compatible-endpoint.example"
~/.codex/codex-deepseek-switch.sh on your-model-name
```

Manually enable thinking mode:

```bash
export CODEX_DEEPSEEK_THINKING=enabled
~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro
```

Note: enabling thinking can make complex tool workflows more likely to show tool calls as plain text or fail in later turns because the context no longer matches the proxy conversion.

## API Key

You do not need to put the API key in project code.

When you turn the proxy on, the script prompts for the API key and stores it in the current macOS user's launch environment with:

```bash
launchctl setenv CODEX_DEEPSEEK_KEY "..."
```

This lets Codex Desktop read the key even when launched from the app icon. The key is not written to project files, README files, scripts, or Git commits.

Check whether it is set:

```bash
launchctl getenv CODEX_DEEPSEEK_KEY
```

Clear it:

```bash
launchctl unsetenv CODEX_DEEPSEEK_KEY
```

If you ever pasted a key into chat logs, public repositories, or other unsafe places, revoke it in the DeepSeek console and create a new one.

## Uninstall

```bash
bash scripts/uninstall.sh
```

Uninstall will:

- Try to restore `~/.codex/config.toml`.
- Remove proxy and helper scripts installed in `~/.codex`.
- Stop the local proxy on port `4446`.
- Clear related macOS launch environment variables.
- Remove `~/.codex/deepseek-proxy.log`.
- Remove `~/.codex/deepseek-usage.jsonl`.

## Limitations

- This is not an official DeepSeek integration.
- Tool calls are best-effort. The proxy forwards prior tool calls as native `tool_calls` messages and tries to recover occasional `Tool call ...` text emitted by DeepSeek back into executable tool calls; complex schemas or long tool chains may still fail.
- Image input is dropped.
- Web search, long-running agentic tasks, and complex multi-tool workflows are usually less reliable than official Codex models.
- Some Codex Desktop account, sync, or product features may still depend on OpenAI / ChatGPT services and cannot be fully replaced by a local proxy.
