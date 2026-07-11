# Codex Mobile Remote Control Troubleshooting

记录时间：2026-05-30

仓库命令统一通过稳定入口运行；每个新 shell 会话先设置：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
```

## 问题现象

- 手机扫码 Codex Desktop 的连接入口后，最初没有反应或登录流程报错。
- 重新登录后，手机端能进入 Codex，但显示 `mac-mini` 离线。
- 本机 `codex remote-control start --json` 显示 daemon 已连接，但手机端仍看不到在线设备。

## 根因

本机同时存在两类远程控制环境：

- `Codex Desktop` 环境：手机端设备列表实际使用这个环境。
- CLI daemon 环境：`codex remote-control start` 启动并显示在线的是这个环境。

当时 CLI daemon 带了代理环境变量，所以它能连上远程控制 websocket；但 Codex Desktop 是从 GUI/Dock/Finder 路径启动的，没有继承终端里的代理变量，导致手机端实际使用的 `Codex Desktop` 环境在云端显示 `online: false`。

简化说：看起来 Mac 端“有一个 Codex 在线”，但手机端看的不是那个在线环境。

## 关键证据

### 1. 手机端只看见 Codex Desktop 环境

通过云端环境列表确认，手机可见的环境是：

```json
{
  "display_name": "mac-mini",
  "client_type": "CODEX_DESKTOP_APP",
  "client_name": "Codex Desktop",
  "online": false
}
```

### 2. CLI daemon 在线但不是手机端选择的环境

```bash
env -u OPENAI_API_KEY -u CODEX_API_KEY \
  HTTPS_PROXY=http://127.0.0.1:7890 \
  HTTP_PROXY=http://127.0.0.1:7890 \
  ALL_PROXY=socks5h://127.0.0.1:7890 \
  codex remote-control start --json
```

返回的环境 ID 是 daemon 环境，不是手机端列表里的 `Codex Desktop` 环境。

### 3. Desktop 进程最初没有代理

```bash
ps eww -p <CodexDesktopPID> | rg -o '(HTTPS_PROXY|HTTP_PROXY|ALL_PROXY)=[^ ]+'
ps eww -p <DesktopAppServerPID> | rg -o '(HTTPS_PROXY|HTTP_PROXY|ALL_PROXY)=[^ ]+'
```

没有输出，说明从 GUI 启动的 Codex Desktop 没继承终端代理。

### 4. 修复后手机请求真正到达 Mac

日志中出现：

```text
app_server.client_name="codex_chatgpt_ios_remote"
app_server.client_version="1.2026.132"
method="initialize"
method="thread/list"
```

这比单纯看到 `online: true` 更强，说明手机端已经通过远程控制通道连到了这台 Mac。

## 修复步骤

### 1. 给 macOS GUI 会话设置代理

```bash
launchctl setenv HTTPS_PROXY http://127.0.0.1:7890
launchctl setenv HTTP_PROXY http://127.0.0.1:7890
launchctl setenv ALL_PROXY socks5h://127.0.0.1:7890
```

这会影响后续从 Dock、Finder、`open -a` 启动的 GUI 应用。需要取消时：

```bash
launchctl unsetenv HTTPS_PROXY
launchctl unsetenv HTTP_PROXY
launchctl unsetenv ALL_PROXY
```

### 2. 重启 Codex Desktop

```bash
osascript -e 'tell application "Codex" to quit' >/dev/null 2>&1 || true
open -a Codex
```

### 3. 验证 Desktop 和 app-server 都继承了代理

```bash
pgrep -fl 'Codex.app/Contents/MacOS/Codex|Codex.app/Contents/Resources/codex app-server --analytics-default-enabled'
ps eww -p <PID> | rg -o '(HTTPS_PROXY|HTTP_PROXY|ALL_PROXY)=[^ ]+'
```

### 4. 验证云端设备在线

不要打印或复制 token。只在本机临时执行：

```bash
curl -sS --connect-timeout 20 --max-time 40 \
  -x http://127.0.0.1:7890 \
  -H @<(printf 'Authorization: Bearer %s\n' "$(jq -r '.tokens.access_token' ~/.codex/auth.json)") \
  'https://chatgpt.com/backend-api/codex/remote/control/environments?limit=100'
```

成功时 `Codex Desktop` 对应的 `mac-mini` 应为：

```json
{
  "client_name": "Codex Desktop",
  "online": true
}
```

### 5. 验证手机端真正连入

让手机刷新或重新扫码，然后在 Mac 上看日志：

```bash
sqlite3 ~/.codex/logs_2.sqlite \
'SELECT datetime(ts,"unixepoch"), level, target, substr(feedback_log_body,1,1000)
 FROM logs
 WHERE ts >= strftime("%s","now","-5 minutes")
   AND target LIKE "codex_app_server%"
   AND (
     feedback_log_body LIKE "%codex_chatgpt_ios_remote%"
     OR feedback_log_body LIKE "%remoteControl/status/changed%"
   )
 ORDER BY ts DESC
 LIMIT 80;'
```

看到 `codex_chatgpt_ios_remote`、`initialize`、`model/list`、`thread/start` 或 `thread/resume`，基本可以确认手机侧已经连上。

## 经验

- 不要只相信 `codex remote-control start --json`。它证明 CLI daemon 在线，不一定证明手机端使用的 Codex Desktop 环境在线。
- 手机端设备列表以云端 `/codex/remote/control/environments` 返回为准；优先看 `client_name`、`client_type`、`online`、`last_seen_at`。
- Codex CLI 版本和 Codex Desktop 内置 CLI 版本可能不同。本次是系统 CLI `0.135.0`，Desktop 内置 CLI `0.133.0`。
- macOS GUI 应用不自动继承当前终端的代理变量。需要用 `launchctl setenv`，然后通过 `open -a Codex` 或 Dock/Finder 重新启动。
- 不要让 Codex Desktop app-server 继承 `CODEX_API_KEY` / `OPENAI_API_KEY`。本次后续验证发现，Desktop app-server 带着 API key 时，插件会灰掉或提示需要 ChatGPT 登录；修复方式是清掉 GUI API-key 环境，并用干净环境启动 Desktop。
- 如果要让 Desktop/手机远程控制消耗 gaccode API 额度，使用单独的 `GACCODE_API_KEY`。当前配置已经验证：ChatGPT 登录负责远程控制，`model_provider = "gaccode"` 负责模型调用；实际请求会打到 `https://gaccode.com/codex/v1/responses`。
- 如果手机端卡在模型列表或长时间加载，检查是否有 `missing field models`。当前修复是把 `model_catalog_json` 配置为当前用户 `~/.codex/gaccode-model-catalog.json` 的绝对路径，让 `model/list` 使用本地模型目录，生成请求继续走 `gaccode /responses`。
- 如果模型调用返回 `402 Payment Required: Access denied: No active subscription`，说明本地路由已经到 gaccode，但当前 gaccode key/订阅不可用。
- 最强验证不是“显示在线”，而是日志中出现手机客户端请求，例如 `codex_chatgpt_ios_remote` 的 `thread/start` 或 `thread/resume`；如果要证明模型额度路径，还要看到同一手机请求链路下的 `POST to https://gaccode.com/codex/v1/responses`。
- 尽量先用 UI 或进程环境修复；不要直接 patch `/Applications/Codex.app`，也不要贸然删 `~/.codex` 数据库。

一键修复 Desktop 环境：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh fix-desktop
```

验证手机是否真正触发 gaccode 模型请求：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh verify-phone-model
```

一次性检查当前目标的机器可验证状态：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh verify-all
```

这个命令会检查 Desktop app-server 环境、ChatGPT 登录状态、云端远控环境、手机线程到 `gaccode /responses` 的证据、插件补丁标记、App 签名、插件补丁测试和已启用插件数量。它不能替代最后的视觉检查：Codex Desktop 插件页不能再显示“需要使用 ChatGPT 登录”的灰色门禁。

如果要现场监听下一次手机发送：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh watch-phone --wait 120
```

现场监听运行后，在手机进入 `mac-mini`，发送 `PHONE_OK`。成功时会看到 `codex_chatgpt_ios_remote -> gaccode /responses`。验证脚本会按同一个 `thread_id` 关联手机进入线程和后续模型请求；模型请求日志本身不一定重复带 `codex_chatgpt_ios_remote`。

如果脚本刚重启 Desktop 后立刻显示 `online: false`，先等 30-60 秒再运行：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh status
```
