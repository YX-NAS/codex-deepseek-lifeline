#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$CODEX_HOME"

install -m 700 "$REPO_DIR/bin/codex-deepseek-proxy.js" "$CODEX_HOME/codex-deepseek-proxy.js"

cat > "$CODEX_HOME/deepseek.config.toml" <<'TOML'
model_provider = "deepseek_proxy"
model = "deepseek-chat"
model_reasoning_effort = "low"

[model_providers.deepseek_proxy]
name = "DeepSeek via local proxy"
base_url = "http://127.0.0.1:4446/v1"
env_key = "CODEX_DEEPSEEK_KEY"
wire_api = "responses"
requires_openai_auth = false
request_max_retries = 2
stream_max_retries = 1
stream_idle_timeout_ms = 120000
TOML

cat > "$CODEX_HOME/start-deepseek-proxy.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [ -z "${CODEX_DEEPSEEK_KEY:-}" ]; then
  echo "CODEX_DEEPSEEK_KEY is not set."
  echo "Run: export CODEX_DEEPSEEK_KEY='your-new-deepseek-key'"
  exit 1
fi

export CODEX_PROXY_TARGET="${CODEX_PROXY_TARGET:-https://api.deepseek.com}"
export CODEX_MODEL="${CODEX_MODEL:-deepseek-chat}"
exec node "$HOME/.codex/codex-deepseek-proxy.js"
SH

cat > "$CODEX_HOME/codex-deepseek-exec.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [ -z "${CODEX_DEEPSEEK_KEY:-}" ]; then
  echo "CODEX_DEEPSEEK_KEY is not set."
  echo "Run: export CODEX_DEEPSEEK_KEY='your-new-deepseek-key'"
  exit 1
fi

exec /Applications/Codex.app/Contents/Resources/codex --profile deepseek "$@"
SH

cat > "$CODEX_HOME/codex-deepseek-on.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

CONFIG="$HOME/.codex/config.toml"
BACKUP="$HOME/.codex/config.toml.before-deepseek"
TMP="$HOME/.codex/config.toml.deepseek-tmp"

if [ ! -f "$CONFIG" ]; then
  echo "Missing $CONFIG"
  exit 1
fi

if [ ! -f "$BACKUP" ]; then
  cp "$CONFIG" "$BACKUP"
fi

{
  cat <<'TOML'
# BEGIN DEEPSEEK FALLBACK
model_provider = "deepseek_proxy"
model = "deepseek-chat"
model_reasoning_effort = "low"

[model_providers.deepseek_proxy]
name = "DeepSeek via local proxy"
base_url = "http://127.0.0.1:4446/v1"
env_key = "CODEX_DEEPSEEK_KEY"
wire_api = "responses"
requires_openai_auth = false
request_max_retries = 2
stream_max_retries = 1
stream_idle_timeout_ms = 120000
# END DEEPSEEK FALLBACK

TOML
  awk '
    /^# BEGIN DEEPSEEK FALLBACK$/ { skip=1; next }
    /^# END DEEPSEEK FALLBACK$/ { skip=0; next }
    skip { next }
    /^\[/ { section=$0 }
    section == "" && $0 ~ /^(model|model_provider|model_reasoning_effort)[[:space:]]*=/ { next }
    { print }
  ' "$BACKUP"
} > "$TMP"

mv "$TMP" "$CONFIG"
echo "Codex default config is now DeepSeek fallback."
echo "Start the proxy first, then fully restart Codex Desktop."
echo "Restore with: ~/.codex/codex-deepseek-off.sh"
SH

cat > "$CODEX_HOME/codex-deepseek-off.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

CONFIG="$HOME/.codex/config.toml"
BACKUP="$HOME/.codex/config.toml.before-deepseek"

if [ ! -f "$BACKUP" ]; then
  echo "No DeepSeek fallback backup found at $BACKUP"
  exit 1
fi

cp "$BACKUP" "$CONFIG"
rm -f "$BACKUP"
echo "Codex default config restored."
echo "Fully restart Codex Desktop to return to the normal setup."
SH

chmod 700 \
  "$CODEX_HOME/start-deepseek-proxy.sh" \
  "$CODEX_HOME/codex-deepseek-exec.sh" \
  "$CODEX_HOME/codex-deepseek-on.sh" \
  "$CODEX_HOME/codex-deepseek-off.sh" \
  "$CODEX_HOME/codex-deepseek-proxy.js"

echo "Installed Codex DeepSeek Lifeline into $CODEX_HOME"
echo "No API key was stored."
