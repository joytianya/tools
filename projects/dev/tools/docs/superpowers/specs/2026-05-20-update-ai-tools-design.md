# Design: Unified AI Tools Update Script

## Overview

Replace the three existing files (`codex-auto-update`, `codex-auto-update.service`, `codex-auto-update.timer`) and integrate `update-ai-tools.sh` from `git@github.com:joytianya/tools.git` into a single unified solution.

## Files

| File | Replaces |
|------|----------|
| `update-ai-tools` | `codex-auto-update` + `update-ai-tools.sh` |
| `update-ai-tools.service` | `codex-auto-update.service` |
| `update-ai-tools.timer` | `codex-auto-update.timer` |

## Main Script (`update-ai-tools`)

**Shell:** `bash`, `set -Eeuo pipefail`

**Environment variables (overridable):**
- `LOG_FILE` — default: `~/.local/share/update-ai-tools/update.log`
- `LOCK_FILE` — default: `~/.local/share/update-ai-tools/update.lock`

**Execution flow:**
1. Create log and lock directories
2. Acquire `flock` on `LOCK_FILE`; exit 0 if already locked
3. Source nvm if `$NVM_DIR/nvm.sh` exists (fallback: `~/.nvm/nvm.sh`)
4. Update Claude Code: run `claude update` if `claude` is on PATH; log version after; skip (no error) if not found
5. Update Codex: run `npm install -g @openai/codex` if `npm` is on PATH; log version after; skip (no error) if not found
6. Log completion

**Run as:** ordinary user (no root requirement). systemd unit runs as the invoking user.

## systemd Units

**`update-ai-tools.service`:**
- `Type=oneshot`
- `ExecStart=<absolute path to script>`
- `Environment=NPM_CONFIG_UPDATE_NOTIFIER=false`
- `Wants=network-online.target`, `After=network-online.target`

**`update-ai-tools.timer`:**
- `OnCalendar=*-*-* 03:30:00`
- `RandomizedDelaySec=30m`
- `Persistent=true`
- `WantedBy=timers.target`

## Removed Files

- `codex-auto-update`
- `codex-auto-update.service`
- `codex-auto-update.timer`
