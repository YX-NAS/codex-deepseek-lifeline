"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const DEFAULT_TARGET = "https://api.deepseek.com";

const BUILTIN_MODELS = [
  {
    id: "deepseek-v4-flash",
    displayName: "DeepSeek V4 Flash",
    provider: "DeepSeek",
    targetBase: DEFAULT_TARGET,
    billingCurrency: "auto",
    thinkingDefault: "disabled",
    codexToolsRecommended: true,
    capabilities: ["fast", "coding", "tool-calls"],
    recommendedFor: "Fast daily Codex fallback and lightweight coding.",
    pricesPer1M: {
      CNY: { inputCacheHit: 0.02, inputCacheMiss: 1, output: 2 },
      USD: { inputCacheHit: 0.0028, inputCacheMiss: 0.14, output: 0.28 }
    }
  },
  {
    id: "deepseek-v4-pro",
    displayName: "DeepSeek V4 Pro",
    provider: "DeepSeek",
    targetBase: DEFAULT_TARGET,
    billingCurrency: "auto",
    thinkingDefault: "disabled",
    codexToolsRecommended: true,
    capabilities: ["stronger", "coding", "tool-calls"],
    recommendedFor: "Higher-capability Codex fallback when quality matters more than cost.",
    pricesPer1M: {
      CNY: { inputCacheHit: 0.025, inputCacheMiss: 3, output: 6 },
      USD: { inputCacheHit: 0.003625, inputCacheMiss: 0.435, output: 0.87 }
    }
  },
  {
    id: "deepseek-chat",
    displayName: "DeepSeek Chat",
    provider: "DeepSeek",
    targetBase: DEFAULT_TARGET,
    billingCurrency: "auto",
    thinkingDefault: "disabled",
    codexToolsRecommended: true,
    capabilities: ["chat", "coding", "tool-calls"],
    recommendedFor: "Official DeepSeek chat-compatible model name.",
    pricesPer1M: {
      CNY: { inputCacheHit: 0.02, inputCacheMiss: 1, output: 2 },
      USD: { inputCacheHit: 0.0028, inputCacheMiss: 0.14, output: 0.28 }
    }
  },
  {
    id: "deepseek-reasoner",
    displayName: "DeepSeek Reasoner",
    provider: "DeepSeek",
    targetBase: DEFAULT_TARGET,
    billingCurrency: "auto",
    thinkingDefault: "disabled",
    codexToolsRecommended: false,
    capabilities: ["reasoning", "chat"],
    recommendedFor: "Reasoning experiments; less reliable for Codex tool-call workflows.",
    pricesPer1M: {
      CNY: { inputCacheHit: 0.02, inputCacheMiss: 1, output: 2 },
      USD: { inputCacheHit: 0.0028, inputCacheMiss: 0.14, output: 0.28 }
    }
  }
];

function defaultCodexHome() {
  return process.env.CODEX_HOME || path.join(os.homedir(), ".codex");
}

function customModelsPath(codexHome = defaultCodexHome()) {
  return process.env.CODEX_DEEPSEEK_CUSTOM_MODELS || path.join(codexHome, "deepseek-models.custom.json");
}

function normalizeCustomModel(model) {
  if (!model || typeof model !== "object" || typeof model.id !== "string" || !model.id.trim()) {
    return null;
  }
  return {
    id: model.id.trim(),
    displayName: model.displayName || model.id.trim(),
    provider: model.provider || "Custom",
    targetBase: model.targetBase || DEFAULT_TARGET,
    billingCurrency: model.billingCurrency || "auto",
    thinkingDefault: model.thinkingDefault || "disabled",
    codexToolsRecommended: Boolean(model.codexToolsRecommended),
    capabilities: Array.isArray(model.capabilities) ? model.capabilities : ["custom"],
    recommendedFor: model.recommendedFor || model.notes || "Custom OpenAI-compatible model.",
    notes: model.notes || "",
    pricesPer1M: model.pricesPer1M || null,
    custom: true
  };
}

function loadCustomModels(codexHome = defaultCodexHome()) {
  const file = customModelsPath(codexHome);
  if (!fs.existsSync(file)) return { file, models: [], errors: [] };
  try {
    const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    const rawModels = Array.isArray(parsed) ? parsed : parsed.models;
    if (!Array.isArray(rawModels)) {
      return { file, models: [], errors: [`${file}: expected an array or an object with a models array`] };
    }
    const models = [];
    const errors = [];
    for (const raw of rawModels) {
      const model = normalizeCustomModel(raw);
      if (model) models.push(model);
      else errors.push(`${file}: skipped custom model without a valid id`);
    }
    return { file, models, errors };
  } catch (error) {
    return { file, models: [], errors: [`${file}: ${error.message}`] };
  }
}

function loadModelCatalog(options = {}) {
  const codexHome = options.codexHome || defaultCodexHome();
  const custom = loadCustomModels(codexHome);
  const byId = new Map();
  for (const model of BUILTIN_MODELS) byId.set(model.id, { ...model, source: "built-in" });
  for (const model of custom.models) byId.set(model.id, { ...model, source: "custom" });
  return {
    models: [...byId.values()],
    errors: custom.errors,
    customFile: custom.file
  };
}

function findModel(id, options = {}) {
  const catalog = loadModelCatalog(options);
  return {
    model: catalog.models.find((item) => item.id === id) || null,
    errors: catalog.errors,
    customFile: catalog.customFile
  };
}

function resolveModel(id, options = {}) {
  const requestedId = id || "deepseek-v4-flash";
  const { model, errors, customFile } = findModel(requestedId, options);
  if (!model) {
    return {
      id: requestedId,
      displayName: requestedId,
      provider: "Unknown",
      targetBase: options.targetOverride || DEFAULT_TARGET,
      billingCurrency: options.billingCurrency || "auto",
      thinkingDefault: options.thinking || "disabled",
      pricesPer1M: null,
      source: "unknown",
      hasPricing: false,
      warning: `Model '${requestedId}' is not in the model catalog; cost estimates will show n/a.`,
      errors,
      customFile
    };
  }
  const billingCurrency = options.billingCurrency && options.billingCurrency !== "auto"
    ? options.billingCurrency
    : model.billingCurrency || "auto";
  return {
    ...model,
    targetBase: options.targetOverride || model.targetBase || DEFAULT_TARGET,
    billingCurrency,
    thinkingDefault: options.thinking || model.thinkingDefault || "disabled",
    hasPricing: Boolean(model.pricesPer1M),
    warning: "",
    errors,
    customFile
  };
}

function priceForModel(id, currency, options = {}) {
  const resolved = resolveModel(id, options);
  const table = resolved.pricesPer1M || null;
  return table ? table[currency] || null : null;
}

function formatModelRows(models) {
  const headers = ["ID", "Name", "Provider", "Tools", "Pricing", "Source"];
  const rows = models.map((model) => [
    model.id,
    model.displayName,
    model.provider || "",
    model.codexToolsRecommended ? "yes" : "caution",
    model.pricesPer1M ? "yes" : "n/a",
    model.source || ""
  ]);
  const widths = headers.map((header, index) => Math.max(header.length, ...rows.map((row) => String(row[index]).length)));
  const line = (row) => row.map((cell, index) => String(cell).padEnd(widths[index])).join("  ");
  return [line(headers), line(widths.map((width) => "-".repeat(width))), ...rows.map(line)].join("\n");
}

function shellQuote(value) {
  return `'${String(value ?? "").replace(/'/g, "'\\''")}'`;
}

function cli() {
  const command = process.argv[2] || "list";
  const codexHome = command === "env" ? process.argv[4] || defaultCodexHome() : process.argv[3] || defaultCodexHome();
  if (command === "list") {
    const catalog = loadModelCatalog({ codexHome });
    console.log(formatModelRows(catalog.models));
    if (catalog.errors.length) {
      console.log("");
      console.log("Custom model warnings:");
      for (const error of catalog.errors) console.log(`- ${error}`);
    }
    console.log("");
    console.log(`custom_models=${catalog.customFile}`);
    return;
  }
  if (command === "json") {
    const catalog = loadModelCatalog({ codexHome });
    console.log(JSON.stringify(catalog));
    return;
  }
  if (command === "env") {
    const id = process.argv[3] || "deepseek-v4-flash";
    const targetOverride = process.argv[5] || "";
    const billingCurrency = process.argv[6] || "auto";
    const resolved = resolveModel(id, {
      codexHome,
      targetOverride: targetOverride || undefined,
      billingCurrency
    });
    console.log(`MODEL=${shellQuote(resolved.id)}`);
    console.log(`MODEL_DISPLAY=${shellQuote(resolved.displayName)}`);
    console.log(`MODEL_PROVIDER=${shellQuote(resolved.provider)}`);
    console.log(`MODEL_TARGET=${shellQuote(resolved.targetBase)}`);
    console.log(`MODEL_THINKING=${shellQuote(resolved.thinkingDefault)}`);
    console.log(`MODEL_BILLING_CURRENCY=${shellQuote(resolved.billingCurrency)}`);
    console.log(`MODEL_HAS_PRICING=${resolved.hasPricing ? "1" : "0"}`);
    console.log(`MODEL_SOURCE=${shellQuote(resolved.source)}`);
    console.log(`MODEL_WARNING=${shellQuote(resolved.warning || resolved.errors.join("; "))}`);
    return;
  }
  console.error("Usage: model-catalog.js [list|json|env model codexHome targetOverride billingCurrency]");
  process.exit(1);
}

if (require.main === module) cli();

module.exports = {
  BUILTIN_MODELS,
  DEFAULT_TARGET,
  customModelsPath,
  loadCustomModels,
  loadModelCatalog,
  findModel,
  resolveModel,
  priceForModel,
  formatModelRows
};
