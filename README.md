# Tools

面向个人 macOS 开发与运维场景的脚本工具箱，包含 Codex Desktop 维护、Codex 远程控制、Shell 环境、网络代理、音频桥接、数据迁移和仓库辅助工具。

## 使用约定

仓库内的稳定入口统一放在 `bin/`。不要从 `apps/`、`platform/`、`integrations/` 或 `tooling/` 直接调用实现文件；这样后续调整内部目录时，外部命令和 LaunchAgent 不需要再次迁移。

每个新 shell 会话先设置仓库位置：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
```

然后通过稳定入口执行，例如：

```bash
$TOOLS_HOME/bin/codex-after-update-fix.sh --diagnose-only
$TOOLS_HOME/bin/codex-remote-account-switch.sh status
$TOOLS_HOME/bin/ssh-tunnel.sh status
```

## 目录导航

| 目录 | 用途 | 示例 |
|---|---|---|
| `bin/` | 用户、自动任务和外部配置的稳定入口 | Codex 更新、远程控制、代理、审计 |
| `apps/` | 只服务某个具体软件的工具 | Codex、Vibe Kanban |
| `platform/` | 可被多个软件复用的机器级能力 | Shell、网络 |
| `integrations/` | 连接两个系统或协议的适配器 | Paseo 与 edge-tts |
| `tooling/` | 管理 Codex Skills 或仓库自身的工具 | Skill Audit、目录结构检查 |
| `docs/` | 当前结构说明与历史资料 | 分类规则、迁移归档 |
| `.local/` | 本机样本和临时产物，不纳入 Git | Codex bundle 样本 |

完整分类规则、模块位置和入口映射见 [docs/STRUCTURE.md](docs/STRUCTURE.md)。

## 常用入口

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}

# Codex Desktop 更新、补丁与恢复
$TOOLS_HOME/bin/codex-after-update-fix.sh --diagnose-only
$TOOLS_HOME/bin/fix-codex-plugins.sh
$TOOLS_HOME/bin/codex-restore-pinned-threads.sh

# Codex 远程控制
$TOOLS_HOME/bin/codex-remote-account-switch.sh status
$TOOLS_HOME/bin/codex-restart-daemons.sh --remote-only
$TOOLS_HOME/bin/codex-sync-remote-ssh-projects.sh --dry-run

# 机器能力与集成
$TOOLS_HOME/bin/ssh-tunnel.sh status
$TOOLS_HOME/bin/proxy7980.sh
$TOOLS_HOME/bin/shell-setup.sh --help
$TOOLS_HOME/bin/paseo-edge-tts-bridge.sh

# 仓库工具
$TOOLS_HOME/bin/skill-audit-generate.sh
```

各脚本参数以对应入口的 `--help` 或模块文档为准。Codex 远程控制的完整手册位于 [apps/codex/remote-control/codex-mobile-remote-tools.md](apps/codex/remote-control/codex-mobile-remote-tools.md)。

## 安全边界

- 一部分命令会修改 `/Applications/Codex.app`、`~/.codex`、LaunchAgent 或远端服务器；执行前先使用可用的 `status`、`--dry-run`、`--diagnose-only` 入口。
- `fix-codex-plugins.sh` 不带参数时会立即修改 Codex.app；只查看说明时使用 `--help`。
- 认证文件、access key、生成数据、PID、日志和本机 bundle 不应进入 Git。
- 远端服务器上的 `~/start-codex-daemon.sh` 是已部署的稳定路径，不随本仓库目录调整而改变。
- 根目录和 `net/` 下的旧入口仅用于迁移兼容；新调用统一使用 `bin/`。
