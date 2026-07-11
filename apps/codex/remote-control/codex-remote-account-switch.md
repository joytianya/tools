# Codex Remote Account Switch

这个文档记录如何更换用于手机远程控制 Codex Desktop 的 ChatGPT 账号。

仓库命令统一通过稳定入口运行；每个新 shell 会话先设置：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
```

配套脚本：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh
```

当前已配置成双通道：

- ChatGPT 登录账号：负责手机扫码、设备发现、远程控制通道、插件账号能力。
- `gaccode` API key：负责 Codex 的实际模型 provider 和额度消耗。

早先尝试把 `OPENAI_API_KEY` / `CODEX_API_KEY` 全局塞给 Desktop，会让 Desktop 插件/ChatGPT 能力集表现异常；现在已经改为只给 Desktop 注入 `GACCODE_API_KEY`。旧配置备份位于：

```text
~/.codex/config.toml.backup-before-desktop-gaccode-dual-chan-20260530012302
~/.codex/config.toml.backup-before-gaccode-default-20260530005506
```

## 适用场景

- Mac 上的 Codex Desktop 要切换到另一个 ChatGPT 账号。
- 手机 ChatGPT/Codex 要用同一个新账号扫描链接并远程控制 Mac。
- 更换账号后，手机端显示离线或看不到 `mac-mini`。

## 基本原则

- Mac 上的 Codex 登录账号和手机 ChatGPT 登录账号必须一致。
- 新版 Codex App 里，插件、手机扫码、设备发现和远程控制都依赖 ChatGPT 登录态；未登录或被 API-key 环境变量干扰时，插件可能显示灰色。
- 手机端看到的是云端远程控制环境，不是 Codex Desktop 左侧所有本地/SSH 连接的完整镜像。
- 本地终端的 `OPENAI_API_KEY` / `CODEX_API_KEY` 可能干扰账号判断，脚本会在调用 Codex CLI 时临时 unset。
- 不要在 `~/.zshrc` 全局 export `OPENAI_API_KEY` / `CODEX_API_KEY` 给 Desktop；这会让 Desktop app-server 误走 API-key/provider 路径，插件可能变灰并提示需要 ChatGPT 登录。
- Desktop 使用的 API key 变量名是 `GACCODE_API_KEY`，不是 `OPENAI_API_KEY` 或 `CODEX_API_KEY`。
- 如果访问 ChatGPT 需要代理，Codex Desktop 作为 GUI 应用必须通过 `launchctl setenv` 继承代理。

当前配置方式：

- Desktop/mobile 远程控制：保持 ChatGPT 登录，不带 `OPENAI_API_KEY` / `CODEX_API_KEY`。
- Desktop/CLI 模型调用：默认 `model_provider = "gaccode"`。
- `gaccode` 的 key 放在 `~/.codex/gaccode.env`，文件内是 `GACCODE_API_KEY=...`，权限为 `600`。
- `~/.zshrc` 里有 `codex()` 包装函数，只把 `GACCODE_API_KEY` 注入到子 `codex` 进程，不全局 export。

如果 Desktop 插件变灰或提示需要 ChatGPT 登录，优先运行：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh fix-desktop
```

刚重启后的几十秒内，云端环境可能短暂显示 `online: false`。等 30-60 秒再运行 `status` 或 `verify`，以第二次结果为准。

成功状态应包含：

```text
launchctl CODEX_API_KEY=missing
launchctl OPENAI_API_KEY=missing
Desktop app-server CODEX_API_KEY=missing
Desktop app-server OPENAI_API_KEY=missing
Desktop app-server GACCODE_API_KEY=set
Logged in using ChatGPT
```

当前实测模型通道：

```text
thread modelProvider: gaccode
request URL: https://gaccode.com/codex/v1/responses
```

如果看到 `402 Payment Required: Access denied: No active subscription`，说明本地路由已经打到 gaccode，但当前 `GACCODE_API_KEY` 对应账号/订阅不可用，需要更换或续订 gaccode key。

更换 key 时不要把 key 写进命令历史，使用 stdin：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
printf '%s\n' "$NEW_GACCODE_KEY" | $TOOLS_HOME/bin/codex-remote-account-switch.sh update-gaccode-key
$TOOLS_HOME/bin/codex-remote-account-switch.sh fix-desktop
```

## 一键切换账号

运行：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh switch
```

脚本会执行：

- 设置 GUI 代理环境变量。
- 停止 `codex remote-control` daemon。
- 退出 Codex Desktop。
- 执行 `codex logout`。
- 执行 `codex login`，按提示用新 ChatGPT 账号完成登录。
- 重新打开 Codex Desktop。
- 显示当前登录、进程和云端设备状态。

如果代理不是 `127.0.0.1:7890`：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh switch \
  --http-proxy http://127.0.0.1:7890 \
  --all-proxy socks5h://127.0.0.1:7890
```

如果不需要代理：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh switch --no-proxy
```

## 手机端操作

Mac 端脚本完成后：

1. 手机 ChatGPT 退出旧账号。
2. 手机 ChatGPT 登录同一个新账号。
3. 重新扫码，或进入 Codex 设备列表刷新。
4. 点击 `mac-mini`。

## 同步登录到远端机器

本机重新登录成功后，如果要让 `bwg-server-zxw`、`ali-server-zxw` 这类远端机器也作为手机端 remote-control 环境在线，运行：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh sync-remotes
```

这个入口会调用 `codex-sync-auth-to-remotes.sh`：

- 先检查本机 ChatGPT token 是否被云端接受。
- 如果远端没有 `~/start-codex-daemon.sh`，自动上传。
- 如果远端没有 Codex，优先用远端的 `npm`/`pnpm`/`bun`/`yarn` 安装 `@openai/codex` 到用户目录。
- 如果安装访问外网失败，会临时建立 SSH reverse proxy：远端 `127.0.0.1:7890` -> 本机 `127.0.0.1:7890`，再重试安装。
- 备份远端旧的 `~/.codex/auth.json`。
- 把本机 `~/.codex/auth.json` 同步到远端。
- 执行远端 `~/start-codex-daemon.sh reenroll`。

机器列表来自：

```text
$TOOLS_HOME/apps/codex/remote-control/codex-remote-hosts.txt
```

以后新增机器时，在这个文件里加一行 SSH 目标即可，例如 SSH alias、`user@IP` 或能用默认 SSH 用户登录的 IP。

注意：自动安装和反代重试都要求 SSH 已经能连上。如果 SSH 目标本身超时、密钥登录不可用，脚本不能自动修复网络入口；需要先配好 SSH alias、密钥或跳板机。

也可以用新增机器入口，它会把机器写入列表、同步登录、必要时自动安装 Codex，并刷新 Codex Desktop 配置：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-add-remote-server.sh new-server-zxw
```

如果远端安装慢，可以调大安装超时；直接安装超时或失败后，默认会临时建立 SSH reverse proxy 再重试：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-add-remote-server.sh new-server-zxw --install-timeout 300
```

不想自动安装或不想开临时反代时：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-add-remote-server.sh new-server-zxw --no-install
$TOOLS_HOME/bin/codex-add-remote-server.sh new-server-zxw --no-reverse-proxy
```

只同步单台：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh sync-remotes --host bwg-server-zxw
```

watchdog 也会自动处理这种情况：如果本机 ChatGPT token 有效，但某台远端自己的 token 返回 `token_invalidated`，`codex-daemon-watchdog.sh` 会自动调用：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-sync-auth-to-remotes.sh --host <remote>
```

也就是自动同步本机登录态并重新注册远端 daemon。可用下面的环境变量关闭：

```bash
CODEX_WATCHDOG_AUTO_SYNC_REMOTE_AUTH=0
```

## 验证

查看本机和云端状态：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh status
```

`status` 会显示默认 provider、GUI 代理、Desktop app-server 环境状态，以及云端 `mac-mini` 是否在线。

查看远程控制环境和最近手机端连接日志：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh verify
```

成功时应看到：

- 云端环境里 `mac-mini` 的 `online` 为 `true`。
- 日志里出现 `codex_chatgpt_ios_remote`。
- 日志里出现手机端请求，例如 `initialize`、`model/list`、`thread/start` 或 `thread/resume`。

验证模型请求是否实际走 `gaccode`：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh verify-model
```

这个命令会分别测试系统 `codex` 和 Codex Desktop 内置 app-server。成功时会看到 Desktop 线程的 `modelProvider` 为 `gaccode`、`model` 为当前 `~/.codex/config.toml` 顶层模型，并出现 `thread/tokenUsage/updated` 或 `turn/completed`。

## 更新 Codex 或 Codex Desktop 的影响

更新 Codex CLI 或 Codex Desktop 不会影响 ChatGPT 账号的订阅权益；订阅跟账号绑定，不跟本机安装包绑定。

可能受影响的是本地连接状态：

- Codex Desktop 更新后会重启，远程控制 websocket 会短暂断开。
- Desktop 内置 CLI 版本可能变化，远程控制 enrollment 可能重新握手。
- 如果 Mac 重启或用户会话重登，`launchctl setenv` 设置的代理可能需要重新设置。
- `gaccode.config.toml` 这类 CLI profile 文件通常不会被 Codex Desktop 更新删除。
- 如果你把默认 `config.toml` 改成 API provider，更新后也要重新验证 Desktop 是否仍按预期读取配置。
- 如果更新后手机又显示离线，优先运行：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh fix-desktop
$TOOLS_HOME/bin/codex-remote-account-switch.sh verify
```

不要因为更新后短暂离线就删除 `~/.codex` 数据库。先看云端 `online` 和本地日志。

## Codex Desktop 使用 gaccode provider 的方式

当前版本不能让 Codex Desktop 通过 `-p gaccode` 直接启动：

```bash
codex -p gaccode
```

原因是 Desktop 启动的是：

```text
codex app-server --analytics-default-enabled
```

而当前 CLI 明确限制：`--profile` 只适用于运行类命令，例如 `codex`、`codex exec`、`codex resume`、`codex fork`，不适用于 `codex app-server`、`codex login`。

所以现在采用的是默认配置方式，而不是 Desktop 启动参数：

- `~/.codex/config.toml` 顶层设置 `model_provider = "gaccode"`。
- `~/.codex/config.toml` 顶层把 `model_catalog_json` 设置为当前用户 `~/.codex/gaccode-model-catalog.json` 的绝对路径，避免手机/桌面的 `model/list` 被 gaccode `/models` 的返回格式卡住。
- `[model_providers.gaccode]` 使用 `base_url = "https://gaccode.com/codex/v1"`。
- provider 的 `env_key` 是 `GACCODE_API_KEY`。
- Desktop 通过 `launchctl setenv GACCODE_API_KEY ...` 获取模型 key。
- ChatGPT 登录态仍来自 `~/.codex/auth.json`，用于远程控制和账号能力。

也就是说，不需要把 Codex App patch 成连接另一个本地 server；当前可验证的实现路径是让 Codex Desktop 的 app-server 读取本机默认 config，然后直接请求 `gaccode` 的 API endpoint。ChatGPT 账号只保留在控制面，不负责模型额度。

不要使用下面这种方式：

- 全局 export `OPENAI_API_KEY`。
- 全局 export `CODEX_API_KEY`。
- 用 `launchctl setenv CODEX_API_KEY ...` 让 Desktop 继承。

这些会让 Desktop 更容易进入 API-key 登录/能力判断路径，从而插件变灰或提示需要 ChatGPT 登录。

当前建议：

- 保持 ChatGPT 登录，用于插件、Desktop UI、手机远程控制。
- 保持默认 `model_provider = "gaccode"`，用于模型调用。
- 只用 `GACCODE_API_KEY` 给模型 provider 取 key。
- 不要从带有全局 `CODEX_API_KEY` / `OPENAI_API_KEY` 的 shell 直接启动 Desktop；脚本已改为用干净环境执行 `open -a Codex`。

如果误改了默认 provider，恢复备份：

```bash
cp "$HOME/.codex/config.toml.backup-before-desktop-gaccode-dual-chan-20260530012302" ~/.codex/config.toml
```

然后重启 Codex Desktop：

```bash
osascript -e 'tell application "Codex" to quit' >/dev/null 2>&1 || true
open -a Codex
```

## 为什么手机端和桌面端项目不同步

这是当前最容易误判的地方。

Codex Desktop 里看到的 `vpn_pool`、SSH 远程连接、以及其他远程主机，属于 Desktop 本地发现或保存的连接和项目视图。手机端 Codex 远程控制看到的是云端注册的远程控制环境，例如这台 Mac 的 `mac-mini`。

因此：

- 手机端显示 `mac-mini` 在线，说明它能远程控制这台 Mac。
- 手机端不一定显示 Desktop 里所有 SSH 连接或项目，例如 `vpn_pool`。
- 如果 `vpn_pool` 是远程 SSH 主机上的项目，它的线程/项目数据可能在远端主机的 `~/.codex`，不是本机 `~/.codex`。
- 手机端目前更像是连到一个 app-server 环境，不是完整同步 Desktop 的所有 remote connection host 列表。
- 本地证据显示，云端 `/codex/remote/control/environments` 当前只返回 `mac-mini` 这样的远程控制环境，不返回 Desktop 里的 `vpn_pool` 项目/SSH host 列表。

排查时要分开看：

- 手机端设备在线问题：查 `/codex/remote/control/environments` 和 `codex_chatgpt_ios_remote` 日志。
- Desktop 远程连接问题：查 Desktop 的 remote connection 配置、SSH alias、远端 Codex CLI 登录状态。

因此目前不能保证“云端远程控制列表”和“桌面端项目/远程连接列表”完全一致。脚本能保持的是 Mac 这台远程控制入口在线；`vpn_pool` 是否出现在手机端，取决于 Codex 手机端是否支持展示 Desktop 的 remote connection/project 列表。

## 常用命令

设置 GUI 代理：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh set-proxy
```

取消 GUI 代理：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh unset-proxy
```

设置 GUI `GACCODE_API_KEY`：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh set-gaccode-key
```

取消 GUI `GACCODE_API_KEY`：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh unset-gaccode-key
```

更新本地保存的 `GACCODE_API_KEY`：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
printf '%s\n' "$NEW_GACCODE_KEY" | $TOOLS_HOME/bin/codex-remote-account-switch.sh update-gaccode-key
```

设置 GUI `CODEX_API_KEY`，仅用于明确测试 Desktop API provider，不建议日常启用：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh set-api-key
```

取消 GUI `CODEX_API_KEY`：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh unset-api-key
```

只查看状态：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh status
```

修复 Desktop 插件灰色、误走 API key 或提示需要 ChatGPT 登录：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh fix-desktop
```

只验证手机远程控制：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/codex-remote-account-switch.sh verify
```

## 安全边界

这个脚本不会：

- 修改 `/Applications/Codex.app`。
- 删除 `~/.codex` 数据库。
- 打印真实 access token。
- 修改手机端账号。
