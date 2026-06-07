# tools/ 目录重组方案

## 一句话结论

建议执行重组：把根目录 26 个文件按职责归入 7 个子目录，**安全**——只要保持 `codex-patch/` 与两个根入口脚本冻结（不移动）、并完成 2 处 launchd plist 的外部修正，迁移即可在保留 git 历史的前提下无损完成。

## 现状问题

- **根目录过度扁平**：26 个文件全部堆在仓库根，shell 安装、网络、TTS、Codex 远程、Codex 补丁等完全不同职责的脚本混杂在一起，靠文件名前缀勉强区分，可发现性差。
- **同名脚本易混淆**：根目录的 `fix-codex-plugins.sh` 与 `codex-patch/fix-codex-plugins.sh` 同名，前者只是 9 行的 `exec` 转发壳，后者才是真正的 worker，平铺时极易看错改错。
- **二进制/运行时产物被提交进库**：6 个 `.paseo-edge-tts-*` 测试产物（`.mp3`/`.pcm`/`.log`/`.pid`）已被 git 跟踪，污染版本库且无 `.gitignore` 约束。
- **缺少 README**：没有任何索引说明各脚本用途与入口命令，新读者无从下手。

## 建议目录结构

```text
tools/
├── fix-codex-plugins.sh                         # FROZEN root wrapper -> exec "$SCRIPT_DIR/codex-patch/fix-codex-plugins.sh"
├── codex-after-update-fix.sh                    # FROZEN updater -> FIX_SCRIPT="$TOOLS_DIR/fix-codex-plugins.sh" (same dir)
├── codex-patch/                                 # FROZEN cluster (pinned by 2 external absolute-path callers)
│   ├── fix-codex-plugins.sh                     # worker -> $SCRIPT_DIR/patch-codex-plugins.mjs (+ chrome .mjs if present)
│   ├── patch-codex-plugins.mjs
│   ├── patch-codex-chrome-browser-use.mjs       # pinned by ~/.codex chrome-plugin-recovery skill (abs path)
│   ├── test-patch-codex-plugins.mjs             # pinned by codex-remote-account-switch.sh:688 (abs path)
│   └── SKILL.md
├── shell-setup/
│   ├── universal-installer.sh
│   ├── bash-enhance-setup.sh
│   ├── enable-starship-zsh.sh
│   ├── fix-starship-two-lines.sh
│   └── fix-terminal-startup.sh
├── codex-remote/                                # $SCRIPT_DIR-relative cluster, moves as one unit
│   ├── codex-add-remote-server.sh               # -> hosts.txt, start-daemon, sync (all $SCRIPT_DIR siblings)
│   ├── codex-daemon-watchdog.sh                 # !! EDIT LaunchAgent plist ProgramArguments after move
│   ├── codex-restart-daemons.sh
│   ├── codex-remote-start-daemon.sh
│   ├── codex-sync-remote-ssh-projects.mjs
│   ├── codex-remote-account-switch.sh           # abs ref into codex-patch/ survives (codex-patch frozen)
│   ├── codex-remote-hosts.txt
│   ├── codex-mobile-remote-tools.md             # master runbook; snippets need path updates
│   ├── codex-mobile-remote-control-troubleshooting.md
│   └── codex-remote-account-switch.md
├── net/
│   ├── ssh_tunnel.sh                            # !! EDIT LaunchAgent plist ProgramArguments after move
│   └── proxy7980.py
├── tts/
│   └── paseo-edge-tts-bridge.mjs                # update ~/.codex/rules/default.rules cwd-relative allow rule
└── vibe-kanban/
    └── vibe-kanban-salvage.sh                   # ROOT_DIR (=script/..) default shifts; pass ROOT_DIR to preserve
```

## 分组理由

| 目录 | 内含 | 入口命令 |
|---|---|---|
| `.` (root) | 冻结的 Codex 插件补丁入口，被外部/同级调用方按绝对路径锁定：一键壳脚本与更新后编排器 | `./fix-codex-plugins.sh` · `./codex-after-update-fix.sh` |
| `codex-patch/` | 冻结的 worker，修补 Codex.app asar 使插件 UI 在自定义鉴权下可用，外加 Node 补丁器、测试与 skill 清单（被 `~/.codex` skill 与 `codex-remote-account-switch.sh` 按绝对路径锁定） | `./codex-patch/fix-codex-plugins.sh` |
| `shell-setup/` | 跨平台 shell/CLI 环境安装器（现代工具链、Starship 提示符、bash 增强、终端启动修复） | `./shell-setup/universal-installer.sh install` |
| `codex-remote/` | Codex 移动端/远程控制守护进程管理（add/restart/start/sync/account-switch）、看门狗、主机列表与操作手册 | `./codex-remote/codex-add-remote-server.sh` · `./codex-remote/codex-restart-daemons.sh` |
| `net/` | 网络辅助：持久反向 SSH 隧道（autossh）与感知系统代理的正向代理 | `./net/ssh_tunnel.sh on` · `python3 ./net/proxy7980.py` |
| `tts/` | 独立 Node TTS/ASR 桥接，通过 edge-tts 暴露 OpenAI 兼容的音频端点 | `node ./tts/paseo-edge-tts-bridge.mjs` |
| `vibe-kanban/` | 一次性 Vibe Kanban 数据迁移/抢救到 v2 SQLite schema | `ROOT_DIR=... ./vibe-kanban/vibe-kanban-salvage.sh` |

## 安全迁移说明

**核心原理：同一 `$SCRIPT_DIR` 簇整体移动，内部引用自然存活。** 各脚本通过 `$SCRIPT_DIR`（脚本自身所在目录）解析同级文件与相对导入，只要把一个簇整体搬进同一个新目录，簇内的相互引用路径不变，无需任何代码改动：

- `codex-patch/` 五个文件是一个 `$SCRIPT_DIR` + 相对 import 簇（worker 调 `node "$SCRIPT_DIR/patch-codex-plugins.mjs"`、chrome `.mjs`，test 用 `import "./patch-codex-plugins.mjs"`）——整簇**冻结不动**。
- `codex-remote/` 各脚本通过 `$SCRIPT_DIR` 解析 `hosts.txt` 与同级脚本——整簇一起搬入 `codex-remote/`，每个查找都保留。
- 根 `fix-codex-plugins.sh` → `$SCRIPT_DIR/codex-patch/...`（冻结的父子关系）；`codex-after-update-fix.sh` → `$TOOLS_DIR/fix-codex-plugins.sh`（同根目录同级）；`codex-remote-account-switch.sh` → `codex-patch/` 的**绝对路径**引用（目标冻结，存活）。

**为什么冻结 `codex-patch/` 与两个根入口（最关键决策）**：它同时满足一条约束链——更新器需要壳脚本作同目录同级、壳脚本需要 `codex-patch/` 作其直接子目录、且仓库**外部**有两个调用方按绝对路径锁定 `codex-patch/`（`~/.codex` chrome-plugin-recovery skill 锁 `patch-codex-chrome-browser-use.mjs`；`codex-remote-account-switch.sh` 锁 `test-patch-codex-plugins.mjs`）。把 `codex-patch/` 钉在原绝对路径，account-switch 脚本就能自由迁入 `codex-remote/` 而其目标零改动仍有效。

**需要的少量跨目录编辑（仅文档快照）**：迁移后对 `codex-remote/` 下三个 `.md` 共 10 处复制粘贴用的绝对路径片段做更新——`codex-mobile-remote-tools.md`（hosts.txt、add-remote-server、restart-daemons、remote-start-daemon、sync、daemon-watchdog、ssh_tunnel 各路径加子目录段）、`codex-mobile-remote-control-troubleshooting.md` 与 `codex-remote-account-switch.md`（account-switch.sh 路径）。这些是非破坏性的文档片段，运行时脚本仍靠 `$SCRIPT_DIR` 解析，不影响执行；编辑须在 `git mv` 之后、对新路径上的文件执行。

**externalUpdates（仓库外的耦合处理）**：
- **HARD** `~/Library/LaunchAgents/com.matrix.ssh-tunnel.plist`：ProgramArguments 硬编码 `.../tools/ssh_tunnel.sh`（RunAtLoad+KeepAlive），改为 `.../tools/net/ssh_tunnel.sh` 后 `launchctl bootout`+`bootstrap` 重载。
- **HARD** `~/Library/LaunchAgents/com.matrix.codex-daemon-watchdog.plist`：ProgramArguments 硬编码 `.../tools/codex-daemon-watchdog.sh`（StartInterval=300），改为 `.../tools/codex-remote/codex-daemon-watchdog.sh` 后重载；其 `$SCRIPT_DIR` 同级随之移动，无需其他改动。
- **SOFT** `~/.codex/rules/default.rules:27,32`：cwd 相对的 `./paseo-edge-tts-bridge.mjs` 允许规则；移动后仅当 codex cwd=tts/ 才匹配。从 `tts/` 启动或更新两条 prefix_rule。
- **SOFT** `vibe-kanban/vibe-kanban-salvage.sh`：`ROOT_DIR` 默认从 `dev/` 偏移到 `dev/tools/`；传 `ROOT_DIR=/Users/matrix/projects/dev` 可保持原默认。
- **无需改动**：`~/.codex` chrome-plugin-recovery skill 与 `~/.codex/config.toml` 的 trust_level（path-keyed，路径未变）；`codex-patch/SKILL.md`（未移动）。

## 校验结果

评审结论：**pass**。无未安置文件（unplacedFiles 为空），无破损引用（brokenRefs 为空）。

requiredFixes（必须处理）：
- **HARD**：改 `com.matrix.ssh-tunnel.plist` ProgramArguments 指向 `net/ssh_tunnel.sh` 并重载（plist 已存在且为旧硬编码路径，已核实）。
- **HARD**：改 `com.matrix.codex-daemon-watchdog.plist` ProgramArguments 指向 `codex-remote/codex-daemon-watchdog.sh` 并重载（同上已核实）。
- **SEQUENCING**：10 处文档编辑必须在 `git mv` 之后执行——每处都针对新路径上的文件，先编辑会因文件尚不在该路径而失败。
- **RECOMMENDED（非破坏）**：vibe-kanban 用 `ROOT_DIR=/Users/matrix/projects/dev` 调用以保持原行为。
- **RECOMMENDED（非破坏）**：更新 `~/.codex/rules/default.rules` 的 paseo prefix_rule 或始终从 `tts/` 启动桥接。

risks（已知风险，均已被方案覆盖）：
- vibe-kanban `ROOT_DIR` 默认随深度偏移（SOFT，有 override，但默认行为确实改变）。
- default.rules 的 cwd 相对允许规则在移动后静默停止匹配（SOFT，不影响执行）。
- `.gitignore` 的宽泛模式（`*.log`/`*.pid`/`*.mp3`/`*.pcm`）可能误忽略未来文件；且加 `.gitignore` **不会**自动取消跟踪已提交的 6 个 `.paseo` 产物，必须实际运行 `git rm --cached`。
- `config.toml` trust 仅注册 `tools/` 与 `tools/codex-patch/`，新子目录预期继承父目录 trust（建议确认）。
- 文档编辑的 find 串共享 `.../tools/` 前缀，但均为精确全路径且替换插入子目录段，单遍应用不会二次误匹配（已核实安全）。

## 如何执行

1. 建议在新分支上操作并提交，使回滚简单。
2. 从**仓库根目录**运行迁移脚本：

   ```bash
   cd /Users/matrix/projects/dev/tools
   ./migrate.sh
   ```

   脚本会先校验自身位于仓库根（检测哨兵文件 `universal-installer.sh`），再执行 `mkdir`/`git mv`、应用 10 处文档编辑、追加 `.gitignore` 行，并对 6 个已跟踪产物执行 `git rm --cached`。脚本**不**触碰两个 launchd plist——请按上文 externalUpdates 手动改 plist 并重载。

3. 回滚命令：

   - 提交前（未 commit）：`git restore --staged --worktree -- .`（撤销所有已暂存/工作区改动；未跟踪的 `.omc/` 会话文件不受影响），随后 `rmdir` 清掉新建的空目录。
   - 已提交且未推送：`git reset --hard <移动前的-sha>`。
   - 已提交（保险做法）：`git revert <sha>`（生成安全的反向提交）。
   - 若已改过两个 launchd plist，需把 ProgramArguments 指回原 `.../tools/ssh_tunnel.sh` 与 `.../tools/codex-daemon-watchdog.sh` 并重载（`bootout`+`bootstrap gui/$(id -u)`）。全程不丢历史。
