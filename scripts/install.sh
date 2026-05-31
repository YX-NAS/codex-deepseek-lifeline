#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
if [ -z "$NODE_BIN" ]; then
  for candidate in /opt/homebrew/bin/node /usr/local/bin/node /usr/bin/node; do
    if [ -x "$candidate" ]; then
      NODE_BIN="$candidate"
      break
    fi
  done
fi
if [ -z "$NODE_BIN" ]; then
  echo "node is required but was not found."
  exit 1
fi
mkdir -p "$CODEX_HOME"

install -m 700 "$REPO_DIR/bin/codex-deepseek-proxy.js" "$CODEX_HOME/codex-deepseek-proxy.js"

cat > "$CODEX_HOME/deepseek.config.toml" <<'TOML'
model_provider = "deepseek_proxy"
model = "deepseek-v4-flash"
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
export CODEX_MODEL="${CODEX_MODEL:-deepseek-v4-flash}"
export CODEX_DEEPSEEK_THINKING="${CODEX_DEEPSEEK_THINKING:-disabled}"
SH
printf 'exec "%s" "$HOME/.codex/codex-deepseek-proxy.js"\n' "$NODE_BIN" >> "$CODEX_HOME/start-deepseek-proxy.sh"

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

if [ -x "$HOME/.codex/codex-deepseek-switch.sh" ]; then
  exec "$HOME/.codex/codex-deepseek-switch.sh" on "$@"
fi

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
model = "deepseek-v4-flash"
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

if [ -x "$HOME/.codex/codex-deepseek-switch.sh" ]; then
  exec "$HOME/.codex/codex-deepseek-switch.sh" off "$@"
fi

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

cat > "$CODEX_HOME/codex-deepseek-switch.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CODEX_HOME/config.toml"
BACKUP="$CODEX_HOME/config.toml.before-deepseek"
TMP="$CODEX_HOME/config.toml.deepseek-tmp"
LOG="$CODEX_HOME/deepseek-proxy.log"
PLIST="$HOME/Library/LaunchAgents/com.codex.deepseek-lifeline.plist"
LABEL="com.codex.deepseek-lifeline"
HOST="${CODEX_DEEPSEEK_PROXY_HOST:-127.0.0.1}"
PORT="${CODEX_DEEPSEEK_PROXY_PORT:-4446}"
TARGET="${CODEX_PROXY_TARGET:-https://api.deepseek.com}"
MODEL="${2:-${CODEX_MODEL:-deepseek-v4-flash}}"
THINKING="${CODEX_DEEPSEEK_THINKING:-disabled}"

usage() {
  cat <<EOF
Usage:
  ~/.codex/codex-deepseek-switch.sh on [model]
  ~/.codex/codex-deepseek-switch.sh off
  ~/.codex/codex-deepseek-switch.sh status

Examples:
  ~/.codex/codex-deepseek-switch.sh on
  ~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro
  ~/.codex/codex-deepseek-switch.sh off
EOF
}

set_launch_env() {
  if command -v launchctl >/dev/null 2>&1; then
    launchctl setenv "$1" "$2" >/dev/null 2>&1 || true
  fi
}

unset_launch_env() {
  if command -v launchctl >/dev/null 2>&1; then
    launchctl unsetenv "$1" >/dev/null 2>&1 || true
  fi
}

get_launch_env() {
  if command -v launchctl >/dev/null 2>&1; then
    launchctl getenv "$1" 2>/dev/null || true
  fi
}

listener_pids() {
  lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true
}

stop_proxy() {
  if command -v launchctl >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
  fi

  local pids
  pids="$(listener_pids)"
  if [ -n "$pids" ]; then
    kill $pids 2>/dev/null || true
    sleep 0.5
  fi
}

write_launch_agent() {
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$CODEX_HOME/start-deepseek-proxy.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$LOG</string>
  <key>StandardErrorPath</key>
  <string>$LOG</string>
  <key>WorkingDirectory</key>
  <string>$HOME</string>
</dict>
</plist>
PLIST
}

write_config() {
  if [ ! -f "$CONFIG" ]; then
    echo "Missing $CONFIG"
    exit 1
  fi

  if [ ! -f "$BACKUP" ]; then
    cp "$CONFIG" "$BACKUP"
  fi

  {
    cat <<TOML
# BEGIN DEEPSEEK FALLBACK
model_provider = "deepseek_proxy"
model = "$MODEL"
model_reasoning_effort = "low"

[model_providers.deepseek_proxy]
name = "DeepSeek via local proxy"
base_url = "http://$HOST:$PORT/v1"
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
}

restore_config() {
  if [ -f "$BACKUP" ]; then
    cp "$BACKUP" "$CONFIG"
    rm -f "$BACKUP"
  fi
}

require_key() {
  local existing_key
  existing_key="${CODEX_DEEPSEEK_KEY:-$(get_launch_env CODEX_DEEPSEEK_KEY)}"
  if [ -n "$existing_key" ]; then
    CODEX_DEEPSEEK_KEY="$existing_key"
    export CODEX_DEEPSEEK_KEY
    return
  fi

  printf "DeepSeek API Key: "
  IFS= read -rs CODEX_DEEPSEEK_KEY
  printf "\n"
  if [ -z "$CODEX_DEEPSEEK_KEY" ]; then
    echo "CODEX_DEEPSEEK_KEY is required."
    exit 1
  fi
  export CODEX_DEEPSEEK_KEY
}

start_proxy() {
  stop_proxy
  export CODEX_MODEL="$MODEL"
  export CODEX_PROXY_TARGET="$TARGET"
  export CODEX_DEEPSEEK_PROXY_HOST="$HOST"
  export CODEX_DEEPSEEK_PROXY_PORT="$PORT"
  export CODEX_DEEPSEEK_THINKING="$THINKING"
  write_launch_agent

  if command -v launchctl >/dev/null 2>&1; then
    launchctl bootstrap "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
    launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
  else
    nohup "$CODEX_HOME/start-deepseek-proxy.sh" > "$LOG" 2>&1 &
  fi

  sleep 0.8

  if [ -n "$(listener_pids)" ]; then
    return
  fi

  echo "Failed to start DeepSeek proxy. Log:"
  tail -40 "$LOG" 2>/dev/null || true
  exit 1
}

status() {
  echo "Config:"
  grep -nE "model|model_provider|base_url|deepseek" "$CONFIG" "$CODEX_HOME/deepseek.config.toml" 2>/dev/null || true
  echo
  echo "Proxy:"
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || echo "No proxy listening on $HOST:$PORT"
  if command -v launchctl >/dev/null 2>&1; then
    launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 && echo "LaunchAgent=$LABEL (loaded)" || true
  fi
  echo
  echo "Desktop env:"
  printf "CODEX_MODEL=%s\n" "$(get_launch_env CODEX_MODEL)"
  printf "CODEX_DEEPSEEK_THINKING=%s\n" "$(get_launch_env CODEX_DEEPSEEK_THINKING)"
  if [ -n "$(get_launch_env CODEX_DEEPSEEK_KEY)" ]; then
    echo "CODEX_DEEPSEEK_KEY=(set)"
  else
    echo "CODEX_DEEPSEEK_KEY=(not set)"
  fi
  echo
  echo "Proxy log: $LOG"
}

case "${1:-}" in
  on)
    require_key
    set_launch_env CODEX_DEEPSEEK_KEY "$CODEX_DEEPSEEK_KEY"
    set_launch_env CODEX_MODEL "$MODEL"
    set_launch_env CODEX_PROXY_TARGET "$TARGET"
    set_launch_env CODEX_DEEPSEEK_THINKING "$THINKING"
    write_config
    start_proxy
    echo "DeepSeek fallback is ON."
    echo "Model: $MODEL"
    echo "Thinking: $THINKING"
    echo "Proxy: http://$HOST:$PORT/v1"
    echo "Log: $LOG"
    echo "Fully restart Codex Desktop to use this config."
    ;;
  off)
    stop_proxy
    restore_config
    unset_launch_env CODEX_DEEPSEEK_KEY
    unset_launch_env CODEX_MODEL
    unset_launch_env CODEX_PROXY_TARGET
    unset_launch_env CODEX_DEEPSEEK_THINKING
    rm -f "$PLIST"
    echo "DeepSeek fallback is OFF."
    echo "Fully restart Codex Desktop to return to the normal setup."
    ;;
  status)
    status
    ;;
  *)
    usage
    exit 1
    ;;
esac
SH

chmod 700 \
  "$CODEX_HOME/start-deepseek-proxy.sh" \
  "$CODEX_HOME/codex-deepseek-exec.sh" \
  "$CODEX_HOME/codex-deepseek-switch.sh" \
  "$CODEX_HOME/codex-deepseek-on.sh" \
  "$CODEX_HOME/codex-deepseek-off.sh" \
  "$CODEX_HOME/codex-deepseek-proxy.js"

echo "Installed Codex DeepSeek Lifeline into $CODEX_HOME"
echo "No API key was stored."
