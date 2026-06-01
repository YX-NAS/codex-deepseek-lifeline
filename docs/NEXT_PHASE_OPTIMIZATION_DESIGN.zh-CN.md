# 下一阶段优化设计与技术方案

## 背景

Codex DeepSeek Lifeline 当前通过本地代理把 Codex Responses API 请求转换为 DeepSeek Chat Completions 请求。它已经支持一键切换、代理启动、费用估算、基础工具调用转换，以及对 `Tool call ...` 文本输出的恢复兜底。

下一阶段优化的核心目标是：让 DeepSeek 在 Codex Desktop / Codex CLI 的工具调用场景里更稳定、更可观测、更容易回滚。

## 当前问题

1. 工具调用兼容性仍是最大不稳定来源。
   - DeepSeek 可能偶尔把工具调用输出为普通文本。
   - 长链路工具调用可能积累格式偏差。
   - 复杂 JSON schema 的参数生成可能不稳定。

2. 代理缺少系统化测试。
   - 目前只有 `node --check` 语法检查。
   - 缺少 Responses API 到 Chat Completions 的转换单元测试。
   - 缺少工具调用恢复、流式 SSE、错误响应、费用统计的回归用例。

3. 可观测性还偏基础。
   - 现有日志能看请求目标和费用估算，但不能快速定位“为什么工具调用失败”。
   - 缺少结构化诊断事件和可脱敏的 debug 样本。

4. 配置与切换体验可以继续收敛。
   - `status` 可以更明确地提示风险状态。
   - 安装、升级、重启后是否生效可以更自动化地确认。

## 目标

- 提升工具调用成功率，减少 `Tool call ...` 文本泄漏。
- 建立可重复的测试矩阵，避免后续改动破坏代理协议转换。
- 增强诊断能力，让用户能快速判断是配置、模型、代理还是上游响应问题。
- 保持安装方式简单，不引入重型依赖或复杂后台服务。

## 非目标

- 不把 Lifeline 伪装成官方 Codex 模型。
- 不承诺 DeepSeek 与 OpenAI/Codex 官方模型拥有同等工具调用可靠性。
- 不支持图片输入的完整多模态转发，除非 DeepSeek 目标接口稳定支持对应能力。
- 不在项目代码、配置文件或日志中保存明文 API Key。

## 方案总览

下一阶段分四条线推进：

1. 工具调用协议层增强。
2. 测试与回归保护。
3. 诊断与可观测性。
4. 安装、状态和文档体验。

优先级建议是先做测试与协议层，再做诊断，最后做体验 polish。这样每次优化都有回归保护。

## 1. 工具调用协议层增强

### 1.1 规范化消息转换

当前代理应继续坚持：

- Codex `function_call` 转为 assistant `tool_calls`。
- Codex `function_call_output` 转为 Chat Completions `tool` 消息。
- DeepSeek `tool_calls` 转回 Codex `function_call`。
- DeepSeek 误输出的 `Tool call ...` 文本尽力解析回 Codex `function_call`。

下一步增强：

- 为每个工具调用维护稳定的 call id 映射表。
- 对缺失 `call_id` 的历史消息生成确定性 id，而不是依赖数组位置。
- 对工具参数做轻量校验：必须是 JSON object 字符串；无法解析时保留为文本回答并记录诊断事件。
- 支持从 Markdown fenced code block 中恢复工具调用参数，例如：

```text
Tool call exec_command (call_1):
```json
{"cmd":"pwd"}
```
```

### 1.2 工具选择策略

在 `body.tools` 存在时，代理已经添加系统提示，要求使用结构化工具调用。下一步可以把提示做成可配置策略：

- `strict`：强提示必须使用 tool_calls，适合 Codex 工具场景。
- `balanced`：保留当前行为，适合普通开发问答。
- `off`：不追加代理提示，便于排查上游模型原始行为。

建议环境变量：

```bash
CODEX_DEEPSEEK_TOOL_POLICY=strict|balanced|off
```

默认值建议：`strict`。

### 1.3 JSON 参数修复

DeepSeek 偶尔可能输出接近 JSON 但不完全合法的参数。建议只做保守修复：

- 去除 Markdown code fence。
- 去除参数前后的解释文字。
- 不自动修复缺引号、尾逗号、注释等宽松 JSON，因为这可能改变用户意图。

失败时记录：

```json
{
  "event": "tool_call_recovery_failed",
  "reason": "invalid_json_arguments"
}
```

## 2. 测试与回归保护

### 2.1 拆分可测试模块

当前代理是单文件脚本。建议先保持单文件运行入口，但把核心纯函数移动到内部可导出模块：

```text
bin/codex-deepseek-proxy.js
lib/protocol.js
lib/cost.js
test/protocol.test.js
test/cost.test.js
```

`bin/` 只负责 HTTP server、环境变量和进程生命周期。`lib/` 负责协议转换、费用估算和文本恢复。

### 2.2 测试框架

优先使用 Node 内置测试框架，避免新增依赖：

```bash
node --test
```

建议 package scripts：

```json
{
  "check": "node --check bin/codex-deepseek-proxy.js",
  "test": "node --test"
}
```

### 2.3 必测用例

- 普通用户消息转换。
- developer/system 指令转换。
- Codex `function_call` 转 DeepSeek `tool_calls`。
- Codex `function_call_output` 转 DeepSeek `tool` 消息。
- DeepSeek 原生 `tool_calls` 转 Codex `function_call`。
- `Tool call ...` 纯文本恢复。
- 多个连续文本工具调用恢复。
- 带 Markdown code fence 的参数恢复。
- 非 JSON 参数不执行恢复，只保留普通文本。
- SSE 输出包含工具调用 item。
- 费用估算按 CNY/USD 分别计算。
- 无 usage 时不写费用记录。

## 3. 诊断与可观测性

### 3.1 结构化诊断日志

保留当前人类可读日志，同时增加 JSONL 诊断日志：

```bash
~/.codex/deepseek-diagnostics.jsonl
```

建议记录事件：

- `request_received`
- `tools_forwarded`
- `tool_call_native_received`
- `tool_call_text_recovered`
- `tool_call_recovery_failed`
- `upstream_error`
- `usage_recorded`

日志必须脱敏：

- 不记录 API Key。
- 默认不记录完整 prompt。
- 工具参数默认只记录长度、hash、工具名和 call id。
- 只有显式开启 debug 时才记录截断样本。

建议环境变量：

```bash
CODEX_DEEPSEEK_DIAGNOSTICS=off|summary|debug
```

默认值建议：`summary`。

### 3.2 status 增强

`~/.codex/codex-deepseek-switch.sh status` 建议增加：

- 当前代理版本。
- installed proxy 是否与仓库版本一致。
- thinking 是否为 `disabled`。
- tool policy 当前值。
- 最近一次工具调用恢复成功/失败次数。
- 最近 5 条诊断事件摘要。

### 3.3 doctor 命令

新增：

```bash
~/.codex/codex-deepseek-switch.sh doctor
```

检查项：

- Node 是否可用，版本是否满足要求。
- API Key 是否存在于 launch 环境。
- 端口 `127.0.0.1:4446` 是否监听。
- `/health` 是否返回正常。
- Codex config 是否指向 `deepseek_proxy`。
- thinking 是否 disabled。
- 最近日志是否有上游错误。

## 4. 安装、升级和回滚体验

### 4.1 安装后自检

`scripts/install.sh` 结束时可以提示：

```text
Installed proxy version: x.y.z
Run status: ~/.codex/codex-deepseek-switch.sh status
```

不建议安装脚本自动开启 DeepSeek，因为需要 API Key 和用户明确选择。

### 4.2 升级安全

安装脚本继续覆盖代理和 helper scripts，但应保留：

- `~/.codex/config.toml.before-deepseek`
- `~/.codex/deepseek-usage.jsonl`
- `~/.codex/deepseek-diagnostics.jsonl`

### 4.3 回滚策略

保留当前：

```bash
~/.codex/codex-deepseek-switch.sh off
```

新增建议：

```bash
~/.codex/codex-deepseek-switch.sh repair
```

作用：

- 停止旧代理。
- 重新写入 `deepseek.config.toml`。
- 重启代理。
- 重新检查 `/health`。

## 分阶段计划

### P0：回归测试基础

产出：

- `lib/protocol.js`
- `lib/cost.js`
- `test/protocol.test.js`
- `test/cost.test.js`
- `npm test`

验收标准：

- `npm run check` 通过。
- `npm test` 通过。
- 当前已修复的 `Tool call ...` 文本恢复行为有测试覆盖。

### P1：工具调用恢复增强

产出：

- `CODEX_DEEPSEEK_TOOL_POLICY`
- Markdown fenced JSON 参数恢复。
- 非法参数恢复失败诊断。
- 多工具调用、混合文本和工具调用的稳定处理。

验收标准：

- 多个连续工具调用可恢复。
- 普通解释文本不会被误解析为工具调用。
- 恢复失败不会触发错误工具执行。

### P2：诊断与 doctor

产出：

- `~/.codex/deepseek-diagnostics.jsonl`
- `CODEX_DEEPSEEK_DIAGNOSTICS`
- `status` 增强。
- `doctor` 命令。

验收标准：

- 用户能从 `status` 看出常见配置问题。
- 诊断日志默认不泄露 prompt、API Key 或完整工具参数。
- 出现工具调用失败时有明确事件记录。

### P3：体验收敛与文档

产出：

- README 更新。
- CHANGELOG 更新。
- skill 排障步骤更新。
- 安装/升级/回滚流程示例。

验收标准：

- 新用户能按 README 安装、开启、查看状态、排查工具调用。
- 旧用户升级后不丢失 usage 日志和配置备份。

## 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 文本恢复误把普通内容当工具调用 | 可能执行非预期工具 | 只识别严格 `Tool call name (id):` 格式，并要求参数是 JSON object |
| 结构化 tool 消息不完全符合 DeepSeek 行为 | 上游请求失败 | 加测试样本和诊断日志，保留降级路径 |
| debug 日志泄露敏感信息 | 安全风险 | 默认 summary；debug 只记录截断和脱敏内容 |
| 模块拆分引入安装路径问题 | 代理无法启动 | 安装脚本同步复制 `lib/`，并在 install 后运行 `node --check` |
| 过度修复 JSON 改变语义 | 工具参数错误 | 不做宽松 JSON 自动修复，只提取合法 JSON |

## 推荐执行顺序

1. 先拆 `lib/protocol.js` 和测试，不改变外部行为。
2. 给当前文本工具调用恢复补齐测试。
3. 增加 fenced JSON 提取和失败诊断。
4. 增加 `CODEX_DEEPSEEK_TOOL_POLICY`。
5. 增加诊断日志和 `doctor`。
6. 更新 README、CHANGELOG 和 skill。
7. 运行安装脚本，在本机确认 installed proxy 与仓库一致。

## 验证命令

```bash
npm run check
npm test
bash scripts/install.sh
~/.codex/codex-deepseek-switch.sh status
~/.codex/codex-deepseek-switch.sh doctor
```

`doctor` 会在 P2 实现，P0/P1 阶段可以先跳过。
