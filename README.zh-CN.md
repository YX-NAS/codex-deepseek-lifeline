# Codex DeepSeek Lifeline

Codex DeepSeek Lifeline 是一个给 Codex Desktop / Codex CLI 使用的本地 DeepSeek 代理。它会把 Codex 的 Responses API 请求转换成 DeepSeek 兼容的 Chat Completions 请求，用来在 Codex 官方额度不可用、或你想临时切到 DeepSeek 时继续工作。

当前版本的主入口是一个一键切换脚本：

```bash
~/.codex/codex-deepseek-switch.sh
```

它会自动完成配置切换、API Key 环境变量设置、本地代理启动/重启和状态检查。正常使用时不需要打开多个终端，也不需要把 API Key 写进代码或配置文件。

## 当前默认

- 默认模型：`deepseek-v4-flash`
- 推荐高能力模型：`deepseek-v4-pro`
- 默认接口：`https://api.deepseek.com`
- 本地代理：`http://127.0.0.1:4446/v1`
- 默认 thinking：`disabled`
- API Key 来源：`CODEX_DEEPSEEK_KEY`

V4 模型默认支持 thinking mode，但 Codex 工具调用需要稳定的上下文转换。这个代理目前默认关闭 thinking：

```bash
CODEX_DEEPSEEK_THINKING=disabled
```

这样可以减少 tool call 被模型当作普通文本输出的情况。

## 安装

```bash
git clone https://github.com/YX-NAS/codex-deepseek-lifeline.git
cd codex-deepseek-lifeline
bash scripts/install.sh
```

安装后会写入这些文件到 `~/.codex`：

```text
~/.codex/codex-deepseek-proxy.js
~/.codex/codex-deepseek-switch.sh
~/.codex/codex-deepseek-on.sh
~/.codex/codex-deepseek-off.sh
~/.codex/start-deepseek-proxy.sh
~/.codex/deepseek.config.toml
```

安装脚本不会保存你的 API Key。

## 一键开启

推荐使用 `deepseek-v4-pro`：

```bash
~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro
```

脚本会提示：

```text
DeepSeek API Key:
```

粘贴你的 DeepSeek API Key 后回车即可。输入过程不会显示明文。

如果不指定模型，默认使用 `deepseek-v4-flash`：

```bash
~/.codex/codex-deepseek-switch.sh on
```

开启时脚本会自动做这些事：

- 把 `CODEX_DEEPSEEK_KEY` 写入 macOS launch 环境，供 Codex Desktop 读取。
- 设置 `CODEX_MODEL`。
- 设置 `CODEX_PROXY_TARGET`。
- 设置 `CODEX_DEEPSEEK_THINKING=disabled`。
- 修改 `~/.codex/config.toml`，把 Codex 默认模型提供方切到本地 DeepSeek 代理。
- 停掉旧的 `4446` 代理进程。
- 在后台启动新的本地代理。
- 把代理日志写到 `~/.codex/deepseek-proxy.log`。

开启后请完全退出并重新打开 Codex Desktop。只开新对话不一定会重新读取配置。

## 检查状态

```bash
~/.codex/codex-deepseek-switch.sh status
```

切换成功时，重点看这些信息：

```text
model_provider = "deepseek_proxy"
model = "deepseek-v4-pro"
base_url = "http://127.0.0.1:4446/v1"
node ... 127.0.0.1:4446 (LISTEN)
CODEX_MODEL=deepseek-v4-pro
CODEX_DEEPSEEK_THINKING=disabled
CODEX_DEEPSEEK_KEY=(set)
```

说明：

- `~/.codex/config.toml` 是 Codex Desktop 当前默认生效配置。
- `~/.codex/deepseek.config.toml` 是备用 profile，默认可能仍显示 `deepseek-v4-flash`。
- 实际请求使用哪个模型，以 `config.toml`、`CODEX_MODEL` 和代理日志为准。

查看代理日志：

```bash
tail -f ~/.codex/deepseek-proxy.log
```

真实请求发生时会看到类似：

```text
target=https://api.deepseek.com model=deepseek-v4-pro thinking=disabled
-> /v1/responses -> https://api.deepseek.com/v1/chat/completions [deepseek-v4-pro]
```

## 关闭并恢复

```bash
~/.codex/codex-deepseek-switch.sh off
```

它会：

- 停止本地代理。
- 恢复切换前备份的 `~/.codex/config.toml`。
- 清除 macOS launch 环境里的 `CODEX_DEEPSEEK_KEY`、`CODEX_MODEL`、`CODEX_PROXY_TARGET` 和 `CODEX_DEEPSEEK_THINKING`。

关闭后同样建议完全退出并重新打开 Codex Desktop。

## 常用命令

```bash
# 开启高能力模型
~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro

# 开启默认快速模型
~/.codex/codex-deepseek-switch.sh on

# 查看状态
~/.codex/codex-deepseek-switch.sh status

# 关闭
~/.codex/codex-deepseek-switch.sh off

# 查看日志
tail -f ~/.codex/deepseek-proxy.log
```

旧命令仍可用：

```bash
~/.codex/codex-deepseek-on.sh
~/.codex/codex-deepseek-off.sh
```

它们会自动转到新的 `codex-deepseek-switch.sh`。

## 配置项

默认值：

```bash
CODEX_PROXY_TARGET=https://api.deepseek.com
CODEX_MODEL=deepseek-v4-flash
CODEX_DEEPSEEK_THINKING=disabled
CODEX_DEEPSEEK_PROXY_HOST=127.0.0.1
CODEX_DEEPSEEK_PROXY_PORT=4446
CODEX_PROXY_MAX_CONCURRENT=1
```

临时改模型：

```bash
~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro
```

临时使用其他 OpenAI-compatible 接口：

```bash
export CODEX_PROXY_TARGET="https://your-compatible-endpoint.example"
~/.codex/codex-deepseek-switch.sh on your-model-name
```

手动开启 thinking mode：

```bash
export CODEX_DEEPSEEK_THINKING=enabled
~/.codex/codex-deepseek-switch.sh on deepseek-v4-pro
```

注意：开启 thinking 后，复杂工具调用可能更容易出现 tool call 被当作普通文本展示、或后续轮次上下文不兼容的问题。

## API Key 说明

不需要在项目代码里填写 API Key。

一键开启时，脚本会提示你输入 API Key，并通过：

```bash
launchctl setenv CODEX_DEEPSEEK_KEY "..."
```

写入当前 macOS 用户的 launch 环境，让从桌面图标启动的 Codex Desktop 也能读取。项目文件、README、脚本和 Git 提交里都不会写入你的 Key。

检查是否已设置：

```bash
launchctl getenv CODEX_DEEPSEEK_KEY
```

清除：

```bash
launchctl unsetenv CODEX_DEEPSEEK_KEY
```

如果你曾经把 Key 粘贴到聊天记录、公开仓库或其他不安全位置，建议立即去 DeepSeek 控制台撤销并重新生成。

## 卸载

```bash
bash scripts/uninstall.sh
```

卸载会：

- 尽量恢复 `~/.codex/config.toml`。
- 删除安装到 `~/.codex` 的代理和辅助脚本。
- 停止 `4446` 上的本地代理。
- 清除相关 macOS launch 环境变量。
- 删除 `~/.codex/deepseek-proxy.log`。

## 限制

- 这是非官方 DeepSeek 集成。
- 工具调用是尽力兼容，复杂 schema 或长链路任务可能失败。
- 图片输入会被丢弃。
- Web search、长时间 agentic 任务、多工具复杂工作流，稳定性通常不如 Codex 官方模型。
- Codex Desktop 的部分账号、同步或产品能力仍可能依赖 OpenAI / ChatGPT 服务，不能只靠本地代理完全替代。
