# Changelog

## 1.4.0

- Added a built-in model catalog for DeepSeek V4 Flash, V4 Pro, Chat, and Reasoner.
- Added custom OpenAI-compatible model support through `~/.codex/deepseek-models.custom.json`.
- Added `~/.codex/codex-deepseek-switch.sh models` and model catalog details in `status`.
- Updated the Web dashboard and terminal UI to list catalog models and manage custom model JSON.
- Updated usage summaries so models without pricing show `estimated_cost=n/a`.

## 1.3.0

- Added a local Web dashboard at `http://127.0.0.1:4456`.
- Added `~/.codex/codex-deepseek-switch.sh ui` for a terminal menu.
- Added dashboard controls for status refresh, model switching, turn-off, usage summaries, and recent logs without accepting API keys in the browser.
- Updated install and uninstall scripts to manage dashboard files.

## 1.2.2

- Repaired dangling or orphaned tool-call histories before forwarding requests to DeepSeek.
- Added recovery for occasional textual `Tool call ...` responses emitted by the upstream model.
- Logged upstream API errors with clearer status, code, and message details.
- Documented current tool-call limitations and the next-phase optimization plan.

## 1.2.1

- Added billing-currency-aware cost estimates with `CODEX_DEEPSEEK_BILLING_CURRENCY=auto|CNY|USD`.
- Added official CNY price table alongside USD pricing.
- Updated cost summaries to display the recorded billing currency instead of always showing USD.

## 1.2.0

- Added token usage and cost-estimate logging to `~/.codex/deepseek-usage.jsonl`.
- Added `codex-deepseek-switch.sh cost` and `codex-deepseek-cost.sh` for total, daily, and tail views.
- Added built-in DeepSeek V4 Flash/Pro pricing estimates based on official per-1M-token prices.
- Updated plugin skill and multilingual README files with cost-estimate usage.

## 1.1.2

- Tightened the plugin skill instructions for disabling DeepSeek Lifeline.
- Documented the fallback when Codex displays tool calls as plain text instead of executing them.

## 1.1.1

- Starts the proxy through a macOS LaunchAgent so plugin-triggered enables keep running reliably.
- Keeps API keys out of the LaunchAgent plist by continuing to use the macOS launch environment.
- Cleans up the LaunchAgent during disable and uninstall flows.

## 1.1.0

- Packaged the project as a Codex plugin with `.codex-plugin/plugin.json`.
- Added the `deepseek-lifeline` skill for enable, disable, status, install, and troubleshooting workflows.
- Updated README files to document plugin usage.

## 1.0.0

- Added the one-command switch workflow with `codex-deepseek-switch.sh`.
- Updated default DeepSeek models to `deepseek-v4-flash` and `deepseek-v4-pro`.
- Disabled DeepSeek thinking mode by default for more stable Codex tool calls.
- Added Chinese and English README files.
- Added status checks, proxy restart handling, and macOS launch environment setup for Codex Desktop.
