#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="$HOME/.local/share/update-ai-tools/update.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# nvm 环境（crontab 不加载 .bashrc，需手动 source）
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

log "===== 开始更新 AI 工具 ====="

# 更新 Claude Code
log "--- 更新 Claude Code ---"
if command -v claude &>/dev/null; then
    claude update 2>&1 | tee -a "$LOG_FILE" || log "Claude Code 更新失败（可能已是最新版）"
    log "Claude Code 版本: $(claude --version 2>&1 | head -1)"
else
    log "未找到 claude 命令，跳过"
fi

# 更新 Codex
log "--- 更新 Codex ---"
if command -v npm &>/dev/null; then
    npm update -g @openai/codex 2>&1 | tee -a "$LOG_FILE" || log "Codex 更新失败"
    log "Codex 版本: $(codex --version 2>&1 | head -1)"
else
    log "未找到 npm 命令，跳过"
fi

log "===== 更新完成 ====="
