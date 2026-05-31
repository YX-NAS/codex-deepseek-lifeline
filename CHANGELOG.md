# Changelog

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
