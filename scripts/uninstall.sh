#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

if [ -f "$CODEX_HOME/config.toml.before-deepseek" ]; then
  cp "$CODEX_HOME/config.toml.before-deepseek" "$CODEX_HOME/config.toml"
  rm -f "$CODEX_HOME/config.toml.before-deepseek"
fi

rm -f \
  "$CODEX_HOME/codex-deepseek-proxy.js" \
  "$CODEX_HOME/deepseek.config.toml" \
  "$CODEX_HOME/start-deepseek-proxy.sh" \
  "$CODEX_HOME/codex-deepseek-exec.sh" \
  "$CODEX_HOME/codex-deepseek-on.sh" \
  "$CODEX_HOME/codex-deepseek-off.sh"

echo "Removed Codex DeepSeek Lifeline files from $CODEX_HOME"
