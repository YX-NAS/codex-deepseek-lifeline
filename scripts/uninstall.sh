#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
PLIST="$HOME/Library/LaunchAgents/com.codex.deepseek-lifeline.plist"
LABEL="com.codex.deepseek-lifeline"

if command -v launchctl >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
  launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
fi

if command -v launchctl >/dev/null 2>&1; then
  launchctl unsetenv CODEX_DEEPSEEK_KEY >/dev/null 2>&1 || true
  launchctl unsetenv CODEX_MODEL >/dev/null 2>&1 || true
  launchctl unsetenv CODEX_PROXY_TARGET >/dev/null 2>&1 || true
  launchctl unsetenv CODEX_DEEPSEEK_THINKING >/dev/null 2>&1 || true
  launchctl unsetenv CODEX_DEEPSEEK_BILLING_CURRENCY >/dev/null 2>&1 || true
fi

if lsof -tiTCP:4446 -sTCP:LISTEN >/dev/null 2>&1; then
  kill $(lsof -tiTCP:4446 -sTCP:LISTEN) 2>/dev/null || true
fi

if lsof -tiTCP:4456 -sTCP:LISTEN >/dev/null 2>&1; then
  kill $(lsof -tiTCP:4456 -sTCP:LISTEN) 2>/dev/null || true
fi

if [ -f "$CODEX_HOME/config.toml.before-deepseek" ]; then
  cp "$CODEX_HOME/config.toml.before-deepseek" "$CODEX_HOME/config.toml"
  rm -f "$CODEX_HOME/config.toml.before-deepseek"
fi

rm -f \
  "$CODEX_HOME/codex-deepseek-proxy.js" \
  "$CODEX_HOME/codex-deepseek-dashboard.js" \
  "$CODEX_HOME/deepseek.config.toml" \
  "$CODEX_HOME/start-deepseek-proxy.sh" \
  "$CODEX_HOME/codex-deepseek-exec.sh" \
  "$CODEX_HOME/codex-deepseek-cost.sh" \
  "$CODEX_HOME/codex-deepseek-dashboard.sh" \
  "$CODEX_HOME/codex-deepseek-switch.sh" \
  "$CODEX_HOME/codex-deepseek-on.sh" \
  "$CODEX_HOME/codex-deepseek-off.sh" \
  "$CODEX_HOME/deepseek-usage.jsonl" \
  "$CODEX_HOME/deepseek-proxy.log" \
  "$CODEX_HOME/deepseek-dashboard.log" \
  "$PLIST"

echo "Removed Codex DeepSeek Lifeline files from $CODEX_HOME"
