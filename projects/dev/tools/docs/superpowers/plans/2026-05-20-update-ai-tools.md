# Update AI Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three legacy `codex-auto-update*` files with a unified `update-ai-tools` script that updates both Claude Code and Codex, plus matching systemd units.

**Architecture:** A single bash script handles both tool updates with flock-based concurrency protection, nvm auto-detection, and per-tool graceful skipping. Two systemd unit files schedule daily execution as the invoking user.

**Tech Stack:** bash, flock, systemd (oneshot service + timer), nvm (optional runtime dependency)

---

### Task 1: Write the main `update-ai-tools` script

**Files:**
- Create: `update-ai-tools`

- [ ] **Step 1: Create the script**

```bash
cat > update-ai-tools << 'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="${LOG_FILE:-$HOME/.local/share/update-ai-tools/update.log}"
LOCK_FILE="${LOCK_FILE:-$HOME/.local/share/update-ai-tools/update.lock}"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$LOCK_FILE")"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "Another update is already running; exiting."
    exit 0
fi

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

log "===== Starting AI tools update ====="

log "--- Updating Claude Code ---"
if command -v claude &>/dev/null; then
    claude update 2>&1 | tee -a "$LOG_FILE" || log "Claude Code update failed (may already be latest)"
    log "Claude Code version: $(claude --version 2>&1 | head -1)"
else
    log "claude not found, skipping"
fi

log "--- Updating Codex ---"
if command -v npm &>/dev/null; then
    npm install -g @openai/codex 2>&1 | tee -a "$LOG_FILE" || log "Codex update failed"
    if command -v codex &>/dev/null; then
        log "Codex version: $(codex --version 2>&1 | head -1)"
    fi
else
    log "npm not found, skipping"
fi

log "===== Update complete ====="
EOF
chmod +x update-ai-tools
```

- [ ] **Step 2: Verify the script is executable and has correct shebang**

```bash
head -1 update-ai-tools && ls -l update-ai-tools
```

Expected output:
```
#!/usr/bin/env bash
-rwxrwxr-x 1 ... update-ai-tools
```

- [ ] **Step 3: Smoke-test with both tools absent (should exit 0 and log skips)**

```bash
LOG_FILE=/tmp/test-update.log PATH=/usr/bin:/bin bash update-ai-tools
grep -E "skipping|complete" /tmp/test-update.log
rm /tmp/test-update.log
```

Expected output contains:
```
claude not found, skipping
npm not found, skipping
===== Update complete =====
```

- [ ] **Step 4: Commit**

```bash
git add update-ai-tools
git commit -m "feat: add unified update-ai-tools script"
```

---

### Task 2: Write the systemd unit files

**Files:**
- Create: `update-ai-tools.service`
- Create: `update-ai-tools.timer`

Note: `ExecStart` uses the absolute path where the script will be installed. The conventional install location for a user-level script is `~/.local/bin/update-ai-tools`. Adjust if deploying elsewhere.

- [ ] **Step 1: Create the service unit**

```bash
cat > update-ai-tools.service << 'EOF'
[Unit]
Description=Update AI tools (Claude Code and Codex)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
Environment=NPM_CONFIG_UPDATE_NOTIFIER=false
ExecStart=%h/.local/bin/update-ai-tools
EOF
```

(`%h` is systemd's specifier for the user's home directory — works correctly with `systemctl --user`.)

- [ ] **Step 2: Create the timer unit**

```bash
cat > update-ai-tools.timer << 'EOF'
[Unit]
Description=Daily AI tools update

[Timer]
OnCalendar=*-*-* 03:30:00
RandomizedDelaySec=30m
Persistent=true
Unit=update-ai-tools.service

[Install]
WantedBy=timers.target
EOF
```

- [ ] **Step 3: Validate unit file syntax**

```bash
systemd-analyze verify update-ai-tools.service update-ai-tools.timer 2>&1 || true
```

Expected: no errors (warnings about missing binary are acceptable at this stage).

- [ ] **Step 4: Commit**

```bash
git add update-ai-tools.service update-ai-tools.timer
git commit -m "feat: add systemd units for update-ai-tools"
```

---

### Task 3: Remove old files

**Files:**
- Delete: `codex-auto-update`
- Delete: `codex-auto-update.service`
- Delete: `codex-auto-update.timer`

- [ ] **Step 1: Remove the old files**

```bash
git rm codex-auto-update codex-auto-update.service codex-auto-update.timer
```

- [ ] **Step 2: Verify they are gone**

```bash
ls -1
```

Expected output (only new files remain):
```
docs/
update-ai-tools
update-ai-tools.service
update-ai-tools.timer
```

- [ ] **Step 3: Commit**

```bash
git commit -m "chore: remove legacy codex-auto-update files"
```

---

### Task 4: Installation instructions verification

This task confirms the deployment steps are correct — no code changes.

- [ ] **Step 1: Verify install path and enable timer (manual step — run when deploying)**

```bash
# Copy script to user bin
mkdir -p ~/.local/bin
cp update-ai-tools ~/.local/bin/update-ai-tools
chmod +x ~/.local/bin/update-ai-tools

# Install and enable systemd user units
mkdir -p ~/.config/systemd/user
cp update-ai-tools.service update-ai-tools.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now update-ai-tools.timer

# Verify timer is active
systemctl --user status update-ai-tools.timer
```

Expected: timer shows `active (waiting)` and next trigger around 03:30.

- [ ] **Step 2: Run once manually to confirm end-to-end**

```bash
systemctl --user start update-ai-tools.service
journalctl --user -u update-ai-tools.service -n 20
```

Expected: log lines showing update attempts for Claude Code and Codex.

- [ ] **Step 3: Final commit (tag the release)**

```bash
git tag v1.0.0
git log --oneline -5
```
