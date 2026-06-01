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
mkdir -p "$CODEX_HOME/lib"

install -m 700 "$REPO_DIR/bin/codex-deepseek-proxy.js" "$CODEX_HOME/codex-deepseek-proxy.js"
install -m 700 "$REPO_DIR/bin/codex-deepseek-dashboard.js" "$CODEX_HOME/codex-deepseek-dashboard.js"
install -m 600 "$REPO_DIR/lib/model-catalog.js" "$CODEX_HOME/lib/model-catalog.js"

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
export CODEX_DEEPSEEK_BILLING_CURRENCY="${CODEX_DEEPSEEK_BILLING_CURRENCY:-auto}"
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

cat > "$CODEX_HOME/codex-deepseek-dashboard.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

export CODEX_DEEPSEEK_DASHBOARD_HOST="${CODEX_DEEPSEEK_DASHBOARD_HOST:-127.0.0.1}"
export CODEX_DEEPSEEK_DASHBOARD_PORT="${CODEX_DEEPSEEK_DASHBOARD_PORT:-4456}"
exec "__NODE_BIN__" "${CODEX_HOME:-$HOME/.codex}/codex-deepseek-dashboard.js"
SH

cat > "$CODEX_HOME/codex-deepseek-cost.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
USAGE_LOG="${CODEX_DEEPSEEK_USAGE_LOG:-$CODEX_HOME/deepseek-usage.jsonl}"
MODE="${1:-summary}"

if [ ! -f "$USAGE_LOG" ]; then
  echo "No usage log found at $USAGE_LOG"
  exit 0
fi

exec "__NODE_BIN__" - "$USAGE_LOG" "$MODE" <<'JS'
const fs = require("node:fs");

const [,, file, mode] = process.argv;
const lines = fs.readFileSync(file, "utf8").split(/\n+/).filter(Boolean);
const records = [];

for (const line of lines) {
  try {
    records.push(JSON.parse(line));
  } catch {
    // Ignore malformed lines so one bad write does not break summaries.
  }
}

function localDateString(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

const today = localDateString(new Date());
const isToday = (record) => {
  if (!record.timestamp) return false;
  const date = new Date(record.timestamp);
  return !Number.isNaN(date.getTime()) && localDateString(date) === today;
};

function summarize(items) {
  const total = {
    requests: items.length,
    input: 0,
    cacheHit: 0,
    cacheMiss: 0,
    output: 0
  };
  const byModel = new Map();
  const byCurrency = new Map();
  let unknownCost = false;

  for (const item of items) {
    const tokens = item.tokens || {};
    const currency = item.billing_currency || (item.estimated_usd ? "USD" : "UNKNOWN");
    const amount = item.estimated_amount || item.estimated_usd || null;
    total.input += tokens.input || 0;
    total.cacheHit += tokens.cacheHit || 0;
    total.cacheMiss += tokens.cacheMiss || 0;
    total.output += tokens.output || 0;

    if (amount && typeof amount.total === "number") {
      byCurrency.set(currency, (byCurrency.get(currency) || 0) + amount.total);
    } else {
      unknownCost = true;
    }

    const model = item.model || "unknown";
    if (!byModel.has(model)) {
      byModel.set(model, { requests: 0, input: 0, cacheHit: 0, cacheMiss: 0, output: 0, currencies: new Map(), unknownCost: false });
    }
    const row = byModel.get(model);
    row.requests += 1;
    row.input += tokens.input || 0;
    row.cacheHit += tokens.cacheHit || 0;
    row.cacheMiss += tokens.cacheMiss || 0;
    row.output += tokens.output || 0;
    if (amount && typeof amount.total === "number") {
      row.currencies.set(currency, (row.currencies.get(currency) || 0) + amount.total);
    } else {
      row.unknownCost = true;
    }
  }

  return { total, byModel, byCurrency, unknownCost };
}

function formatAmounts(amounts, unknownCost = false) {
  if (unknownCost) return "n/a";
  if (!amounts.size) return "n/a";
  return [...amounts.entries()].map(([currency, value]) => `${currency} ${value.toFixed(6)}`).join(", ");
}

function printSummary(title, items) {
  const { total, byModel, byCurrency, unknownCost } = summarize(items);
  console.log(title);
  console.log(`requests=${total.requests}`);
  console.log(`input_tokens=${total.input} cache_hit=${total.cacheHit} cache_miss=${total.cacheMiss} output_tokens=${total.output}`);
  console.log(`estimated_cost=${formatAmounts(byCurrency, unknownCost)}`);
  if (byModel.size) {
    console.log("");
    console.log("by_model:");
    for (const [model, row] of byModel) {
      console.log(`  ${model}: requests=${row.requests} input=${row.input} cache_hit=${row.cacheHit} cache_miss=${row.cacheMiss} output=${row.output} estimated_cost=${formatAmounts(row.currencies, row.unknownCost)}`);
    }
  }
}

if (mode === "today") {
  printSummary(`DeepSeek cost estimate for ${today}`, records.filter(isToday));
} else if (mode === "all" || mode === "summary") {
  printSummary("DeepSeek cost estimate total", records);
  console.log("");
  printSummary(`DeepSeek cost estimate for ${today}`, records.filter(isToday));
} else if (mode === "tail") {
  for (const record of records.slice(-10)) {
    console.log(JSON.stringify(record));
  }
} else {
  console.log("Usage: ~/.codex/codex-deepseek-cost.sh [summary|today|all|tail]");
  process.exit(1);
}

console.log("");
console.log(`source=${file}`);
console.log("note=estimate only; displayed in the recorded billing currency; verify against the DeepSeek billing console for final charges");
JS
SH
NODE_BIN_FOR_TEMPLATE="$NODE_BIN" perl -0pi -e 's#__NODE_BIN__#$ENV{NODE_BIN_FOR_TEMPLATE}#g' "$CODEX_HOME/codex-deepseek-cost.sh"
NODE_BIN_FOR_TEMPLATE="$NODE_BIN" perl -0pi -e 's#__NODE_BIN__#$ENV{NODE_BIN_FOR_TEMPLATE}#g' "$CODEX_HOME/codex-deepseek-dashboard.sh"

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
DASHBOARD_LOG="$CODEX_HOME/deepseek-dashboard.log"
PLIST="$HOME/Library/LaunchAgents/com.codex.deepseek-lifeline.plist"
LABEL="com.codex.deepseek-lifeline"
HOST="${CODEX_DEEPSEEK_PROXY_HOST:-127.0.0.1}"
PORT="${CODEX_DEEPSEEK_PROXY_PORT:-4446}"
TARGET="${CODEX_PROXY_TARGET:-https://api.deepseek.com}"
MODEL="${2:-${CODEX_MODEL:-deepseek-v4-flash}}"
THINKING="${CODEX_DEEPSEEK_THINKING:-disabled}"
BILLING_CURRENCY="${CODEX_DEEPSEEK_BILLING_CURRENCY:-auto}"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
MODEL_CATALOG="$CODEX_HOME/lib/model-catalog.js"

usage() {
  cat <<EOF
Usage:
  ~/.codex/codex-deepseek-switch.sh on [model]
  ~/.codex/codex-deepseek-switch.sh off
  ~/.codex/codex-deepseek-switch.sh status
  ~/.codex/codex-deepseek-switch.sh models
  ~/.codex/codex-deepseek-switch.sh cost [summary|today|all|tail]
  ~/.codex/codex-deepseek-switch.sh ui

Examples:
  ~/.codex/codex-deepseek-switch.sh on
  ~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro
  ~/.codex/codex-deepseek-switch.sh off
  ~/.codex/codex-deepseek-switch.sh models
  ~/.codex/codex-deepseek-switch.sh cost today
  ~/.codex/codex-deepseek-switch.sh ui
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
  export CODEX_DEEPSEEK_BILLING_CURRENCY="$BILLING_CURRENCY"
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
  printf "CODEX_DEEPSEEK_BILLING_CURRENCY=%s\n" "$(get_launch_env CODEX_DEEPSEEK_BILLING_CURRENCY)"
  if [ -n "$(get_launch_env CODEX_DEEPSEEK_KEY)" ]; then
    echo "CODEX_DEEPSEEK_KEY=(set)"
  else
    echo "CODEX_DEEPSEEK_KEY=(not set)"
  fi
  echo
  echo "Model catalog:"
  local status_model
  status_model="$(get_launch_env CODEX_MODEL)"
  if [ -z "$status_model" ]; then
    status_model="$(grep -E '^model[[:space:]]*=' "$CONFIG" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
  fi
  if [ -n "$status_model" ] && [ -n "$NODE_BIN" ] && [ -f "$MODEL_CATALOG" ]; then
    "$NODE_BIN" "$MODEL_CATALOG" env "$status_model" "$CODEX_HOME" "$(get_launch_env CODEX_PROXY_TARGET)" "$(get_launch_env CODEX_DEEPSEEK_BILLING_CURRENCY)" | grep -E "MODEL_DISPLAY|MODEL_PROVIDER|MODEL_TARGET|MODEL_HAS_PRICING|MODEL_SOURCE|MODEL_WARNING" || true
  else
    echo "Model catalog is unavailable."
  fi
  echo
  echo "Proxy log: $LOG"
}

models() {
  if [ -z "$NODE_BIN" ] || [ ! -f "$MODEL_CATALOG" ]; then
    echo "Model catalog is unavailable. Re-run: bash scripts/install.sh"
    exit 1
  fi
  "$NODE_BIN" "$MODEL_CATALOG" list "$CODEX_HOME"
}

resolve_model() {
  if [ -n "$NODE_BIN" ] && [ -f "$MODEL_CATALOG" ]; then
    eval "$("$NODE_BIN" "$MODEL_CATALOG" env "$MODEL" "$CODEX_HOME" "${CODEX_PROXY_TARGET:-}" "$BILLING_CURRENCY")"
    TARGET="$MODEL_TARGET"
    THINKING="${CODEX_DEEPSEEK_THINKING:-$MODEL_THINKING}"
    BILLING_CURRENCY="$MODEL_BILLING_CURRENCY"
  else
    MODEL_DISPLAY="$MODEL"
    MODEL_HAS_PRICING=0
    MODEL_WARNING="Model catalog is unavailable. Re-run: bash scripts/install.sh"
  fi
}

start_dashboard() {
  if lsof -nP -iTCP:4456 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Dashboard already listening on http://127.0.0.1:4456"
  else
    nohup "$CODEX_HOME/codex-deepseek-dashboard.sh" > "$DASHBOARD_LOG" 2>&1 &
    sleep 0.6
    echo "Dashboard: http://127.0.0.1:4456"
    echo "Dashboard log: $DASHBOARD_LOG"
  fi
  if command -v open >/dev/null 2>&1; then
    open "http://127.0.0.1:4456" >/dev/null 2>&1 || true
  fi
}

run_ui() {
  while true; do
    cat <<MENU

Codex DeepSeek Lifeline
1) Status
2) Start default model (deepseek-v4-flash)
3) Start high-capability model (deepseek-v4-pro)
4) Turn off DeepSeek
5) Cost summary
6) Recent proxy log
7) Model catalog
8) Open Web dashboard
0) Exit
MENU
    printf "Choose: "
    IFS= read -r choice
    case "$choice" in
      1) status ;;
      2) "$0" on deepseek-v4-flash ;;
      3) "$0" on deepseek-v4-pro ;;
      4) "$0" off ;;
      5) "$CODEX_HOME/codex-deepseek-cost.sh" summary ;;
      6) tail -80 "$LOG" 2>/dev/null || echo "No proxy log found at $LOG" ;;
      7) models ;;
      8) start_dashboard ;;
      0) exit 0 ;;
      *) echo "Unknown choice: $choice" ;;
    esac
  done
}

case "${1:-}" in
  on)
    require_key
    resolve_model
    set_launch_env CODEX_DEEPSEEK_KEY "$CODEX_DEEPSEEK_KEY"
    set_launch_env CODEX_MODEL "$MODEL"
    set_launch_env CODEX_PROXY_TARGET "$TARGET"
    set_launch_env CODEX_DEEPSEEK_THINKING "$THINKING"
    set_launch_env CODEX_DEEPSEEK_BILLING_CURRENCY "$BILLING_CURRENCY"
    write_config
    start_proxy
    echo "DeepSeek fallback is ON."
    echo "Model: $MODEL"
    echo "Model name: ${MODEL_DISPLAY:-$MODEL}"
    if [ "${MODEL_HAS_PRICING:-0}" != "1" ]; then
      echo "Pricing: n/a"
    fi
    if [ -n "${MODEL_WARNING:-}" ]; then
      echo "Warning: $MODEL_WARNING"
    fi
    echo "Thinking: $THINKING"
    echo "Billing currency: $BILLING_CURRENCY"
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
    unset_launch_env CODEX_DEEPSEEK_BILLING_CURRENCY
    rm -f "$PLIST"
    echo "DeepSeek fallback is OFF."
    echo "Fully restart Codex Desktop to return to the normal setup."
    ;;
  status)
    status
    ;;
  models)
    models
    ;;
  cost)
    exec "$CODEX_HOME/codex-deepseek-cost.sh" "${2:-summary}"
    ;;
  ui)
    run_ui
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
  "$CODEX_HOME/codex-deepseek-cost.sh" \
  "$CODEX_HOME/codex-deepseek-dashboard.sh" \
  "$CODEX_HOME/codex-deepseek-switch.sh" \
  "$CODEX_HOME/codex-deepseek-on.sh" \
  "$CODEX_HOME/codex-deepseek-off.sh" \
  "$CODEX_HOME/codex-deepseek-proxy.js" \
  "$CODEX_HOME/codex-deepseek-dashboard.js"

echo "Installed Codex DeepSeek Lifeline into $CODEX_HOME"
echo "No API key was stored."
