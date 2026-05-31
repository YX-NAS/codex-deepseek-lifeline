#!/usr/bin/env node
"use strict";

const http = require("node:http");
const https = require("node:https");

const PORT = Number(process.env.CODEX_DEEPSEEK_PROXY_PORT || "4446");
const HOST = process.env.CODEX_DEEPSEEK_PROXY_HOST || "127.0.0.1";
const TARGET_BASE = (process.env.CODEX_PROXY_TARGET || "https://api.deepseek.com").replace(/\/+$/, "");
const MODEL_NAME = process.env.CODEX_MODEL || "deepseek-chat";
const API_KEY = process.env.CODEX_DEEPSEEK_KEY || "";
const MAX_CONCURRENT = Number(process.env.CODEX_PROXY_MAX_CONCURRENT || "1");

if (!API_KEY) {
  console.error("CODEX_DEEPSEEK_KEY is not set.");
  console.error("Run: export CODEX_DEEPSEEK_KEY='your-new-deepseek-key'");
  process.exit(1);
}

let activeRequests = 0;
const pendingQueue = [];

function normalizeContent(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return content;
  return content
    .filter((part) => part.type !== "input_image")
    .map((part) => {
      if (part.type === "input_text" || part.type === "output_text") {
        return { type: "text", text: part.text || "" };
      }
      if (typeof part.text === "string") return { type: "text", text: part.text };
      return { type: "text", text: JSON.stringify(part) };
    });
}

function contentToText(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return JSON.stringify(content ?? "");
  return content.map((part) => part?.text || JSON.stringify(part)).join("\n");
}

function outputToText(output) {
  if (typeof output === "string") return output;
  return JSON.stringify(output ?? "");
}

function normalizeRole(role) {
  if (role === "developer") return "system";
  if (role === "assistant" || role === "system" || role === "user") return role;
  if (role === "tool") return "user";
  return "user";
}

function normalizeTool(tool) {
  if (tool?.function) return tool;
  if (tool?.type === "function" || tool?.name) {
    return {
      type: "function",
      function: {
        name: tool.name,
        description: tool.description || "",
        parameters: tool.parameters || { type: "object", properties: {} }
      }
    };
  }
  return null;
}

function responsesToChatCompletions(body) {
  const messages = [];

  if (typeof body.instructions === "string" && body.instructions.trim()) {
    messages.push({ role: "system", content: body.instructions });
  }

  const input = Array.isArray(body.input) ? body.input : [body.input].filter(Boolean);
  for (const item of input) {
    if (typeof item === "string") {
      messages.push({ role: "user", content: item });
      continue;
    }
    if (!item || typeof item !== "object") continue;

    if (item.type === "function_call_output") {
      messages.push({
        role: "user",
        content: `Tool output${item.call_id ? ` (${item.call_id})` : ""}:\n${outputToText(item.output)}`
      });
      continue;
    }

    if (item.type === "function_call") {
      messages.push({
        role: "assistant",
        content: `Tool call${item.name ? ` ${item.name}` : ""}${item.call_id ? ` (${item.call_id})` : ""}:\n${item.arguments || ""}`
      });
      continue;
    }

    if (item.role) {
      const role = normalizeRole(item.role);
      const content = normalizeContent(item.content);
      messages.push({
        role,
        content: item.role === "tool" ? `Tool output:\n${contentToText(content)}` : content
      });
    }
  }

  const result = {
    model: MODEL_NAME,
    messages,
    stream: false
  };

  if (body.max_output_tokens) result.max_tokens = body.max_output_tokens;
  if (body.temperature != null) result.temperature = body.temperature;
  if (body.top_p != null) result.top_p = body.top_p;
  if (body.stop) result.stop = body.stop;

  if (Array.isArray(body.tools)) {
    const tools = body.tools.map(normalizeTool).filter(Boolean);
    if (tools.length) result.tools = tools;
  }
  if (body.tool_choice) {
    if (body.tool_choice === "auto" || body.tool_choice === "none" || body.tool_choice === "required") {
      result.tool_choice = body.tool_choice;
    } else if (typeof body.tool_choice === "object" && body.tool_choice.name) {
      result.tool_choice = {
        type: "function",
        function: { name: body.tool_choice.name }
      };
    } else if (typeof body.tool_choice === "object" && body.tool_choice.function?.name) {
      result.tool_choice = body.tool_choice;
    }
  }

  return result;
}

function normalizeUsage(usage) {
  if (!usage) return null;
  return {
    input_tokens: usage.prompt_tokens || usage.input_tokens || 0,
    output_tokens: usage.completion_tokens || usage.output_tokens || 0,
    total_tokens: usage.total_tokens || 0,
    input_tokens_details: { cached_tokens: usage.prompt_cache_hit_tokens || 0 },
    output_tokens_details: { reasoning_tokens: 0 }
  };
}

function chatCompletionToSse(data) {
  const respId = `resp_${data.id || Date.now()}`;
  const model = data.model || MODEL_NAME;
  const choice = data.choices?.[0] || {};
  const message = choice.message || {};
  const outputItems = [];
  const events = [];

  const push = (event, payload) => {
    events.push(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
  };

  push("response.created", {
    type: "response.created",
    response: { id: respId, object: "response", status: "in_progress", model, output: [] }
  });

  push("response.in_progress", {
    type: "response.in_progress",
    response: { id: respId, object: "response", status: "in_progress", model, output: [] }
  });

  let outputIndex = 0;
  if (message.content) {
    const itemId = `${respId}_msg_0`;
    const text = typeof message.content === "string" ? message.content : JSON.stringify(message.content);
    const item = {
      id: itemId,
      type: "message",
      role: "assistant",
      status: "completed",
      content: [{ type: "output_text", text }]
    };

    push("response.output_item.added", {
      type: "response.output_item.added",
      output_index: outputIndex,
      item: { ...item, status: "in_progress", content: [] }
    });
    push("response.content_part.added", {
      type: "response.content_part.added",
      output_index: outputIndex,
      content_index: 0,
      part: { type: "output_text", text: "" }
    });
    push("response.output_text.delta", {
      type: "response.output_text.delta",
      output_index: outputIndex,
      content_index: 0,
      delta: text
    });
    push("response.output_item.done", {
      type: "response.output_item.done",
      output_index: outputIndex,
      item
    });
    outputItems.push(item);
    outputIndex++;
  }

  for (const tc of message.tool_calls || []) {
    const item = {
      id: tc.id || `${respId}_fc_${outputIndex}`,
      type: "function_call",
      status: "completed",
      call_id: tc.id,
      name: tc.function?.name || "",
      arguments: tc.function?.arguments || ""
    };
    push("response.output_item.added", {
      type: "response.output_item.added",
      output_index: outputIndex,
      item
    });
    push("response.output_item.done", {
      type: "response.output_item.done",
      output_index: outputIndex,
      item
    });
    outputItems.push(item);
    outputIndex++;
  }

  push("response.completed", {
    type: "response.completed",
    response: {
      id: respId,
      object: "response",
      created_at: data.created || Math.floor(Date.now() / 1000),
      status: "completed",
      model,
      output: outputItems,
      usage: normalizeUsage(data.usage)
    }
  });

  return events.join("");
}

function chatCompletionToResponse(data) {
  const choice = data.choices?.[0] || {};
  const message = choice.message || {};
  const output = [];

  if (message.content) {
    output.push({
      type: "message",
      id: data.id || `msg_${Date.now()}`,
      status: "completed",
      role: "assistant",
      content: [{ type: "output_text", text: message.content }]
    });
  }

  for (const tc of message.tool_calls || []) {
    output.push({
      type: "function_call",
      id: tc.id,
      call_id: tc.id,
      name: tc.function?.name || "",
      arguments: tc.function?.arguments || ""
    });
  }

  return {
    id: data.id || `resp_${Date.now()}`,
    object: "response",
    created_at: data.created || Math.floor(Date.now() / 1000),
    status: "completed",
    model: data.model || MODEL_NAME,
    output,
    usage: normalizeUsage(data.usage)
  };
}

function enqueue(task) {
  pendingQueue.push(task);
  processNext();
}

function processNext() {
  if (activeRequests >= MAX_CONCURRENT || pendingQueue.length === 0) return;
  activeRequests++;
  doProxyRequest(pendingQueue.shift()).finally(() => {
    activeRequests--;
    processNext();
  });
}

async function doProxyRequest({ req, res, body }) {
  const chatBody = responsesToChatCompletions(body);
  const postData = JSON.stringify(chatBody);
  const target = new URL(`${TARGET_BASE}/v1/chat/completions`);
  const client = target.protocol === "https:" ? https : http;

  console.log(`-> ${req.url} -> ${target.href} [${chatBody.model}]`);

  await new Promise((resolve) => {
    const upstream = client.request({
      hostname: target.hostname,
      port: target.port || (target.protocol === "https:" ? 443 : 80),
      path: target.pathname + target.search,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(postData),
        "Authorization": `Bearer ${API_KEY}`
      }
    }, (upstreamRes) => {
      let responseData = "";
      upstreamRes.on("data", (chunk) => { responseData += chunk; });
      upstreamRes.on("end", () => {
        try {
          const parsed = JSON.parse(responseData);
          if (parsed.error) {
            res.writeHead(upstreamRes.statusCode || 502, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: parsed.error }));
          } else if (body.stream === false) {
            res.writeHead(upstreamRes.statusCode || 200, { "Content-Type": "application/json" });
            res.end(JSON.stringify(chatCompletionToResponse(parsed)));
          } else {
            res.writeHead(upstreamRes.statusCode || 200, {
              "Content-Type": "text/event-stream",
              "Cache-Control": "no-cache"
            });
            res.end(chatCompletionToSse(parsed));
          }
        } catch (error) {
          res.writeHead(502, { "Content-Type": "application/json" });
          res.end(JSON.stringify({
            error: "Failed to parse upstream response",
            detail: error.message,
            raw: responseData.slice(0, 500)
          }));
        }
        resolve();
      });
    });

    upstream.on("error", (error) => {
      res.writeHead(502, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: `Upstream error: ${error.message}` }));
      resolve();
    });

    upstream.write(postData);
    upstream.end();
  });
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

const server = http.createServer(async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, x-api-key");

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      status: "ok",
      target: TARGET_BASE,
      model: MODEL_NAME,
      queue: pendingQueue.length,
      active: activeRequests
    }));
    return;
  }

  if (req.method !== "POST") {
    res.writeHead(405, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Method not allowed" }));
    return;
  }

  try {
    const body = await readJson(req);
    enqueue({ req, res, body });
  } catch {
    res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Invalid JSON" }));
  }
});

server.listen(PORT, HOST, () => {
  console.log(`codex-deepseek-lifeline proxy listening on http://${HOST}:${PORT}`);
  console.log(`target=${TARGET_BASE} model=${MODEL_NAME}`);
});
