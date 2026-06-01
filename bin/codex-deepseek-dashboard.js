#!/usr/bin/env node
"use strict";

const http = require("node:http");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFile } = require("node:child_process");
let modelCatalog;
try {
  modelCatalog = require("./lib/model-catalog");
} catch {
  modelCatalog = require("../lib/model-catalog");
}

const CODEX_HOME = process.env.CODEX_HOME || path.join(os.homedir(), ".codex");
const HOST = process.env.CODEX_DEEPSEEK_DASHBOARD_HOST || "127.0.0.1";
const PORT = Number(process.env.CODEX_DEEPSEEK_DASHBOARD_PORT || "4456");
const PROXY_HOST = process.env.CODEX_DEEPSEEK_PROXY_HOST || "127.0.0.1";
const PROXY_PORT = Number(process.env.CODEX_DEEPSEEK_PROXY_PORT || "4446");
const SWITCH_SCRIPT = path.join(CODEX_HOME, "codex-deepseek-switch.sh");
const USAGE_LOG = process.env.CODEX_DEEPSEEK_USAGE_LOG || path.join(CODEX_HOME, "deepseek-usage.jsonl");
const PROXY_LOG = path.join(CODEX_HOME, "deepseek-proxy.log");
const CONFIG = path.join(CODEX_HOME, "config.toml");
const DEEPSEEK_CONFIG = path.join(CODEX_HOME, "deepseek.config.toml");

function json(res, status, data) {
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(data));
}

function text(res, status, data, contentType = "text/plain; charset=utf-8") {
  res.writeHead(status, { "Content-Type": contentType });
  res.end(data);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let raw = "";
    req.on("data", (chunk) => { raw += chunk; });
    req.on("end", () => {
      try {
        resolve(raw ? JSON.parse(raw) : {});
      } catch (error) {
        reject(error);
      }
    });
  });
}

function run(command, args, options = {}) {
  return new Promise((resolve) => {
    execFile(command, args, { timeout: options.timeout || 15000 }, (error, stdout, stderr) => {
      resolve({
        ok: !error,
        code: error?.code || 0,
        stdout: stdout || "",
        stderr: stderr || "",
        message: error?.message || ""
      });
    });
  });
}

async function launchEnv(name) {
  const result = await run("launchctl", ["getenv", name], { timeout: 3000 });
  return result.ok ? result.stdout.trim() : "";
}

function readIfExists(file) {
  try {
    return fs.readFileSync(file, "utf8");
  } catch {
    return "";
  }
}

function tailLines(file, count) {
  const content = readIfExists(file);
  if (!content) return [];
  return content.split(/\r?\n/).filter(Boolean).slice(-count);
}

function parseConfigModel(configText) {
  const match = configText.match(/^model\s*=\s*"([^"]+)"/m);
  return match ? match[1] : "";
}

function parseConfigBaseUrl(configText) {
  const match = configText.match(/^base_url\s*=\s*"([^"]+)"/m);
  return match ? match[1] : "";
}

function localDateString(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function summarizeUsage() {
  const lines = tailLines(USAGE_LOG, 5000);
  const today = localDateString(new Date());
  const summary = {
    source: USAGE_LOG,
    total: { requests: 0, input: 0, output: 0, cost: {}, unknownCost: false },
    today: { requests: 0, input: 0, output: 0, cost: {}, unknownCost: false },
    byModel: {}
  };

  for (const line of lines) {
    let record;
    try {
      record = JSON.parse(line);
    } catch {
      continue;
    }
    const tokens = record.tokens || {};
    const currency = record.billing_currency || (record.estimated_usd ? "USD" : "UNKNOWN");
    const amount = record.estimated_amount || record.estimated_usd || null;
    const model = record.model || "unknown";
    const rowDate = record.timestamp ? localDateString(new Date(record.timestamp)) : "";

    const add = (bucket) => {
      bucket.requests += 1;
      bucket.input += tokens.input || 0;
      bucket.output += tokens.output || 0;
      if (amount && typeof amount.total === "number") bucket.cost[currency] = (bucket.cost[currency] || 0) + amount.total;
      else bucket.unknownCost = true;
    };

    add(summary.total);
    if (rowDate === today) add(summary.today);

    if (!summary.byModel[model]) {
      summary.byModel[model] = { requests: 0, input: 0, output: 0, cost: {}, unknownCost: false };
    }
    add(summary.byModel[model]);
  }

  return summary;
}

function formatCost(cost) {
  const entries = Object.entries(cost || {});
  if (!entries.length) return "n/a";
  return entries.map(([currency, value]) => `${currency} ${Number(value).toFixed(6)}`).join(", ");
}

async function proxyHealth() {
  return new Promise((resolve) => {
    const req = http.get({
      hostname: PROXY_HOST,
      port: PROXY_PORT,
      path: "/health",
      timeout: 2500
    }, (res) => {
      let raw = "";
      res.on("data", (chunk) => { raw += chunk; });
      res.on("end", () => {
        try {
          resolve({ online: res.statusCode === 200, data: JSON.parse(raw) });
        } catch {
          resolve({ online: false, data: null });
        }
      });
    });
    req.on("timeout", () => {
      req.destroy();
      resolve({ online: false, data: null });
    });
    req.on("error", () => resolve({ online: false, data: null }));
  });
}

async function statusPayload() {
  const [health, modelEnv, thinkingEnv, currencyEnv, keyEnv] = await Promise.all([
    proxyHealth(),
    launchEnv("CODEX_MODEL"),
    launchEnv("CODEX_DEEPSEEK_THINKING"),
    launchEnv("CODEX_DEEPSEEK_BILLING_CURRENCY"),
    launchEnv("CODEX_DEEPSEEK_KEY")
  ]);
  const configText = readIfExists(CONFIG);
  const fallbackConfigText = readIfExists(DEEPSEEK_CONFIG);
  const currentModel = health.data?.model || modelEnv || parseConfigModel(configText);
  const resolvedModel = modelCatalog.resolveModel(currentModel || "deepseek-v4-flash", {
    codexHome: CODEX_HOME,
    targetOverride: health.data?.target || undefined,
    billingCurrency: health.data?.billing_currency || currencyEnv || "auto",
    thinking: health.data?.thinking || thinkingEnv || "disabled"
  });
  return {
    proxy: {
      online: health.online,
      host: PROXY_HOST,
      port: PROXY_PORT,
      health: health.data
    },
    config: {
      model: parseConfigModel(configText),
      baseUrl: parseConfigBaseUrl(configText),
      fallbackModel: parseConfigModel(fallbackConfigText),
      fallbackBaseUrl: parseConfigBaseUrl(fallbackConfigText)
    },
    model: resolvedModel,
    desktopEnv: {
      model: modelEnv,
      thinking: thinkingEnv,
      billingCurrency: currencyEnv,
      hasKey: Boolean(keyEnv)
    },
    paths: {
      switchScript: SWITCH_SCRIPT,
      usageLog: USAGE_LOG,
      proxyLog: PROXY_LOG
    }
  };
}

async function apiSwitch(req, res) {
  const body = await readJson(req);
  const model = String(body.model || "").trim() || "deepseek-v4-flash";
  const key = await launchEnv("CODEX_DEEPSEEK_KEY");
  if (!key && !process.env.CODEX_DEEPSEEK_KEY) {
    json(res, 409, {
      error: "CODEX_DEEPSEEK_KEY is not available to the desktop environment.",
      command: `~/.codex/codex-deepseek-switch.sh on ${model}`
    });
    return;
  }
  const result = await run(SWITCH_SCRIPT, ["on", model], { timeout: 30000 });
  json(res, result.ok ? 200 : 500, result);
}

async function apiOff(_req, res) {
  const result = await run(SWITCH_SCRIPT, ["off"], { timeout: 30000 });
  json(res, result.ok ? 200 : 500, result);
}

async function apiCustomModels(req, res) {
  const body = await readJson(req);
  const models = Array.isArray(body) ? body : Array.isArray(body.models) ? body.models : [];
  const file = modelCatalog.customModelsPath(CODEX_HOME);
  fs.writeFileSync(file, `${JSON.stringify({ models }, null, 2)}\n`);
  json(res, 200, modelCatalog.loadModelCatalog({ codexHome: CODEX_HOME }));
}

const HTML = String.raw`<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Codex DeepSeek Lifeline</title>
  <style>
    :root { color-scheme: light; --bg:#f7f8fa; --panel:#fff; --text:#162033; --muted:#667085; --line:#d9dee8; --blue:#2563eb; --red:#dc2626; --green:#16a34a; }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: var(--bg); color: var(--text); }
    header { padding: 24px 28px 12px; border-bottom: 1px solid var(--line); background: var(--panel); }
    h1 { margin: 0 0 6px; font-size: 24px; letter-spacing: 0; }
    main { padding: 20px 28px 32px; max-width: 1180px; margin: 0 auto; }
    .grid { display: grid; grid-template-columns: repeat(12, 1fr); gap: 14px; }
    .panel { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 16px; }
    .span-4 { grid-column: span 4; } .span-6 { grid-column: span 6; } .span-8 { grid-column: span 8; } .span-12 { grid-column: span 12; }
    .label { color: var(--muted); font-size: 12px; margin-bottom: 5px; }
    .value { font-size: 18px; font-weight: 650; overflow-wrap: anywhere; }
    .muted { color: var(--muted); }
    .badge { display: inline-flex; align-items: center; gap: 6px; padding: 4px 8px; border-radius: 999px; font-size: 13px; border: 1px solid var(--line); }
    .dot { width: 8px; height: 8px; border-radius: 999px; background: var(--red); }
    .online .dot { background: var(--green); }
    .actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
    button, input, select { border: 1px solid var(--line); border-radius: 7px; padding: 9px 11px; font: inherit; background: #fff; color: var(--text); }
    button { cursor: pointer; font-weight: 600; }
    button.primary { background: var(--blue); border-color: var(--blue); color: #fff; }
    button.danger { background: var(--red); border-color: var(--red); color: #fff; }
    input, select { min-width: 240px; }
    pre { margin: 0; white-space: pre-wrap; overflow-wrap: anywhere; font-size: 12px; line-height: 1.55; color: #263244; }
    table { width: 100%; border-collapse: collapse; font-size: 14px; }
    th, td { text-align: left; padding: 8px 6px; border-bottom: 1px solid var(--line); vertical-align: top; }
    th { color: var(--muted); font-weight: 600; }
    @media (max-width: 820px) { main, header { padding-left: 16px; padding-right: 16px; } .span-4, .span-6, .span-8 { grid-column: span 12; } input { width: 100%; min-width: 0; } }
  </style>
</head>
<body>
  <header>
    <h1>Codex DeepSeek Lifeline</h1>
    <div class="muted">Local dashboard on 127.0.0.1. API keys are not accepted or stored here.</div>
  </header>
  <main>
    <div class="grid">
      <section class="panel span-4">
        <div class="label">Proxy</div>
        <div id="proxyBadge" class="badge"><span class="dot"></span><span>Loading</span></div>
      </section>
      <section class="panel span-4">
        <div class="label">Current Model</div>
        <div id="model" class="value">-</div>
      </section>
      <section class="panel span-4">
        <div class="label">Target</div>
        <div id="target" class="value">-</div>
      </section>
      <section class="panel span-8">
        <div class="label">Controls</div>
        <select id="modelSelect" aria-label="Known models" onchange="document.getElementById('modelInput').value=this.value"></select>
        <input id="modelInput" value="deepseek-v4-pro" aria-label="Model name">
        <div class="actions">
          <button class="primary" onclick="switchModel()">Switch Model</button>
          <button onclick="refreshAll()">Refresh</button>
          <button class="danger" onclick="turnOff()">Turn Off</button>
        </div>
        <p id="message" class="muted"></p>
      </section>
      <section class="panel span-4">
        <div class="label">Desktop Env</div>
        <pre id="env">-</pre>
      </section>
      <section class="panel span-6">
        <div class="label">Usage</div>
        <div id="usage">-</div>
      </section>
      <section class="panel span-6">
        <div class="label">Common Commands</div>
        <pre>~/.codex/codex-deepseek-switch.sh status
~/.codex/codex-deepseek-switch.sh models
~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro
~/.codex/codex-deepseek-switch.sh cost
~/.codex/codex-deepseek-switch.sh off</pre>
      </section>
      <section class="panel span-12">
        <div class="label">Model Catalog</div>
        <div id="models">Loading...</div>
      </section>
      <section class="panel span-12">
        <div class="label">Custom Models JSON</div>
        <textarea id="customModels" rows="8" style="width:100%; border:1px solid var(--line); border-radius:7px; padding:10px; font:12px ui-monospace, SFMono-Regular, Menlo, monospace;"></textarea>
        <div class="actions"><button onclick="saveCustomModels()">Save Custom Models</button></div>
      </section>
      <section class="panel span-12">
        <div class="label">Recent Proxy Log</div>
        <pre id="logs">Loading...</pre>
      </section>
    </div>
  </main>
  <script>
    async function getJson(url, options) {
      const res = await fetch(url, options);
      const data = await res.json();
      if (!res.ok) throw data;
      return data;
    }
    function costText(cost) {
      const entries = Object.entries(cost || {});
      return entries.length ? entries.map(([k, v]) => k + " " + Number(v).toFixed(6)).join(", ") : "n/a";
    }
    function esc(value) {
      return String(value ?? "").replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
    }
    async function refreshStatus() {
      const data = await getJson("/api/status");
      const badge = document.getElementById("proxyBadge");
      badge.className = "badge " + (data.proxy.online ? "online" : "");
      badge.querySelector("span:last-child").textContent = data.proxy.online ? "Online" : "Offline";
      document.getElementById("target").textContent = data.proxy.health?.target || data.config.baseUrl || "-";
      document.getElementById("model").textContent =
        (data.model?.displayName || data.proxy.health?.model || data.desktopEnv.model || data.config.model || "-") +
        (data.model?.hasPricing ? "" : " (pricing n/a)");
      document.getElementById("env").textContent =
        "CODEX_MODEL=" + (data.desktopEnv.model || "") + "\n" +
        "THINKING=" + (data.desktopEnv.thinking || "") + "\n" +
        "BILLING=" + (data.desktopEnv.billingCurrency || "") + "\n" +
        "KEY=" + (data.desktopEnv.hasKey ? "(set)" : "(not set)");
    }
    async function refreshUsage() {
      const data = await getJson("/api/usage");
      const rows = Object.entries(data.byModel || {}).map(([model, row]) =>
        "<tr><td>" + model + "</td><td>" + row.requests + "</td><td>" + row.input + "</td><td>" + row.output + "</td><td>" + (row.unknownCost ? "n/a" : costText(row.cost)) + "</td></tr>"
      ).join("");
      document.getElementById("usage").innerHTML =
        "<p>Total: " + data.total.requests + " requests, " + (data.total.unknownCost ? "n/a" : costText(data.total.cost)) + "</p>" +
        "<p>Today: " + data.today.requests + " requests, " + (data.today.unknownCost ? "n/a" : costText(data.today.cost)) + "</p>" +
        "<table><thead><tr><th>Model</th><th>Req</th><th>Input</th><th>Output</th><th>Cost</th></tr></thead><tbody>" + rows + "</tbody></table>";
    }
    async function refreshModels() {
      const data = await getJson("/api/models");
      const select = document.getElementById("modelSelect");
      select.innerHTML = data.models.map((m) => "<option value='" + esc(m.id) + "'>" + esc(m.displayName) + " (" + esc(m.id) + ")</option>").join("");
      const rows = data.models.map((m) =>
        "<tr><td>" + esc(m.id) + "</td><td>" + esc(m.displayName) + "</td><td>" + esc(m.provider || "") + "</td><td>" + (m.codexToolsRecommended ? "yes" : "caution") + "</td><td>" + (m.pricesPer1M ? "yes" : "n/a") + "</td><td>" + esc(m.source || "") + "</td></tr>"
      ).join("");
      const customModels = data.models.filter((m) => m.source === "custom").map(({ source, custom, ...rest }) => rest);
      document.getElementById("models").innerHTML =
        (data.errors.length ? "<p class='muted'>" + data.errors.map(esc).join("<br>") + "</p>" : "") +
        "<p class='muted'>Custom file: " + esc(data.customFile) + "</p>" +
        "<table><thead><tr><th>ID</th><th>Name</th><th>Provider</th><th>Tools</th><th>Pricing</th><th>Source</th></tr></thead><tbody>" + rows + "</tbody></table>";
      if (!document.getElementById("customModels").value.trim()) {
        document.getElementById("customModels").value = customModels.length ? JSON.stringify({ models: customModels }, null, 2) : "";
      }
      document.getElementById("customModels").placeholder = JSON.stringify({ models: [{ id: "custom-model", displayName: "Custom Model", provider: "Custom", targetBase: "https://api.example.com", notes: "OpenAI-compatible endpoint" }] }, null, 2);
    }
    async function refreshLogs() {
      const data = await getJson("/api/logs");
      document.getElementById("logs").textContent = data.lines.join("\n") || "No log lines yet.";
    }
    async function refreshAll() {
      document.getElementById("message").textContent = "";
      await Promise.all([refreshStatus(), refreshUsage(), refreshLogs(), refreshModels()]);
    }
    async function saveCustomModels() {
      try {
        const text = document.getElementById("customModels").value.trim();
        const body = text ? JSON.parse(text) : { models: [] };
        await getJson("/api/custom-models", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
        document.getElementById("message").textContent = "Custom models saved.";
      } catch (error) {
        document.getElementById("message").textContent = "Invalid custom model JSON: " + (error.message || JSON.stringify(error));
      }
      await refreshModels();
    }
    async function switchModel() {
      const model = document.getElementById("modelInput").value.trim();
      try {
        const data = await getJson("/api/switch", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ model }) });
        document.getElementById("message").textContent = data.stdout || "Switched.";
      } catch (error) {
        document.getElementById("message").textContent = error.command ? ("Run in Terminal: " + error.command) : JSON.stringify(error);
      }
      await refreshAll();
    }
    async function turnOff() {
      const data = await getJson("/api/off", { method: "POST" });
      document.getElementById("message").textContent = data.stdout || "Turned off.";
      await refreshAll();
    }
    refreshAll().catch((error) => { document.getElementById("message").textContent = JSON.stringify(error); });
  </script>
</body>
</html>`;

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === "GET" && req.url === "/") return text(res, 200, HTML, "text/html; charset=utf-8");
    if (req.method === "GET" && req.url === "/api/status") return json(res, 200, await statusPayload());
    if (req.method === "GET" && req.url === "/api/models") return json(res, 200, modelCatalog.loadModelCatalog({ codexHome: CODEX_HOME }));
    if (req.method === "GET" && req.url === "/api/usage") return json(res, 200, summarizeUsage());
    if (req.method === "GET" && req.url === "/api/logs") return json(res, 200, { source: PROXY_LOG, lines: tailLines(PROXY_LOG, 80) });
    if (req.method === "POST" && req.url === "/api/switch") return apiSwitch(req, res);
    if (req.method === "POST" && req.url === "/api/off") return apiOff(req, res);
    if (req.method === "POST" && req.url === "/api/custom-models") return apiCustomModels(req, res);
    json(res, 404, { error: "Not found" });
  } catch (error) {
    json(res, 500, { error: error.message });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`codex-deepseek-dashboard listening on http://${HOST}:${PORT}`);
});
