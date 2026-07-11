# 仓库目录结构

## 分类原则

本仓库使用“所有权优先、能力补充”的混合分类：

1. 只服务一个软件的功能放入 `apps/<software>/`。
2. 可被多个软件复用的机器级能力放入 `platform/<capability>/`。
3. 连接两个系统或协议的适配器放入 `integrations/<owner>/<adapter>/`。
4. 管理 Codex、Skills 或仓库本身的工具放入 `tooling/<ecosystem>/`。
5. 用户、LaunchAgent 和其他外部调用方只依赖 `bin/`。
6. 已完成的一次性仓库迁移放入 `docs/archive/`。
7. 本机样本与临时产物放入 `.local/`，生成数据放入模块自己的 `generated/` 或 `runtime/`，均不纳入 Git。

单文件模块直接放在所属目录中，不为形式统一额外创建空的 `src/`、`lib/` 或 `tests/`。

## 当前布局

```text
tools/
├── README.md
├── bin/                              # 唯一稳定的外部执行入口
├── apps/
│   ├── codex/
│   │   ├── desktop-patch/            # Codex.app 更新与插件/Chrome 补丁
│   │   ├── desktop-recovery/         # Desktop 数据恢复
│   │   └── remote-control/           # 远程 daemon、认证、项目同步、watchdog、SSH tunnel
│   └── vibe-kanban/
│       └── migrations/               # 一次性数据抢救迁移
├── platform/
│   ├── shell/                        # Shell、Starship 与终端环境
│   └── network/                      # 通用代理能力
├── integrations/
│   └── paseo/
│       └── edge-tts/                 # OpenAI 音频接口兼容桥
├── tooling/
│   ├── codex/
│   │   └── skill-audit/              # Skills 审核页面与决策执行器
│   │       ├── generated/            # 生成数据，不纳入 Git
│   │       └── runtime/              # PID、日志等，不纳入 Git
│   └── repo/                         # 仓库结构检查
├── docs/
│   ├── STRUCTURE.md
│   └── archive/                      # 已完成迁移的历史资料
└── .local/                           # 本机样本与临时产物，不纳入 Git
```

## 模块与稳定入口

| 模块 | 实现位置 | `bin/` 入口 |
|---|---|---|
| Codex Desktop 更新与补丁 | `apps/codex/desktop-patch/` | `codex-after-update-fix.sh`、`fix-codex-plugins.sh`、`patch-codex-chrome-browser-use.sh` |
| Codex Desktop 恢复 | `apps/codex/desktop-recovery/` | `codex-restore-pinned-threads.sh` |
| Codex 远程控制 | `apps/codex/remote-control/` | `codex-add-remote-server.sh`、`codex-remote-account-switch.sh`、`codex-restart-daemons.sh`、`codex-daemon-watchdog.sh` |
| Codex 认证与项目同步 | `apps/codex/remote-control/` | `codex-sync-auth-to-remotes.sh`、`codex-sync-remote-ssh-projects.sh` |
| Codex 启动环境 | `apps/codex/remote-control/` | `codex-gaccode-cli-wrapper.sh`、`codex-gaccode-launch-env.sh` |
| Codex SSH tunnel | `apps/codex/remote-control/` | `ssh-tunnel.sh` |
| Shell 环境 | `platform/shell/` | `shell-setup.sh` |
| 通用网络代理 | `platform/network/` | `proxy7980.sh` |
| Paseo 音频桥 | `integrations/paseo/edge-tts/` | `paseo-edge-tts-bridge.sh` |
| Vibe Kanban 迁移 | `apps/vibe-kanban/migrations/` | `vibe-kanban-salvage.sh` |
| Codex Skill Audit | `tooling/codex/skill-audit/` | `skill-audit-generate.sh`、`skill-audit-apply.sh` |

调用格式统一为：

```bash
TOOLS_HOME=${TOOLS_HOME:-$HOME/projects/dev/tools}
$TOOLS_HOME/bin/<entry> [arguments...]
```

`bin/` wrapper 只负责定位仓库根并使用 `exec` 转发，参数、信号和退出码由实际实现处理。实现语言是内部细节：Node 与 Python 工具同样通过 `.sh` 入口调用。

## 新内容如何归类

- 先判断是否只属于一个软件；是则进入该软件的 `apps/` 子树。
- 如果能力可跨软件复用，进入 `platform/`，不要为了当前第一个调用者放进某个 app。
- 如果核心职责是协议转换或系统连接，进入 `integrations/`。
- 如果工具管理的是仓库、Skills 或开发工作流本身，进入 `tooling/`。
- 新增可直接运行的功能时，同时在 `bin/` 添加薄 wrapper；外部配置不得指向实现目录。
- 一次性迁移完成后，将脚本与方案一起归档，并在归档 README 中明确禁止在当前布局执行。

## 兼容与运行时内容

- 根目录 `codex-after-update-fix.sh`、`fix-codex-plugins.sh` 与 `net/ssh_tunnel.sh` 是迁移期兼容入口；新文档和自动任务不得继续引用它们。
- 远端 `~/start-codex-daemon.sh` 是部署接口，不是仓库入口，路径保持不变。
- `.local/`、`tooling/codex/skill-audit/generated/` 和 `runtime/` 只保存可重建或本机专属内容。
- 历史布局说明保留旧路径是为了审计，不代表当前可用入口；当前结构以本文件和根 README 为准。
