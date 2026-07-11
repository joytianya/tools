#!/usr/bin/env bash
# migrate.sh — reorganize the flat tools/ repo into职责子目录.
#
# WHAT THIS DOES (in order):
#   1. Guard: refuse to run unless we're at the repo root (sentinel check).
#   2. mkdir + git mv every relocated file (history-preserving).
#   3. Apply 10 in-place doc-snippet edits to the relocated .md files.
#   4. Append .gitignore rules for runtime/test artifacts.
#   5. git rm --cached the 6 already-tracked artifacts (keeps them on disk).
#
# WHAT THIS DOES NOT DO (handle manually — see reorg-proposal.md externalUpdates):
#   - Edit the two launchd plists (ssh-tunnel, codex-daemon-watchdog).
#   - Touch ~/.codex/rules/default.rules or config.toml.
#   - Commit anything. Review `git status` then commit on a branch.
#
# FROZEN (intentionally NOT moved): fix-codex-plugins.sh, codex-after-update-fix.sh,
#   and the entire codex-patch/ cluster — pinned by a same-dir updater, the
#   root->child wrapper, and two external absolute-path callers.

set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Guard — must run from the repo root.
# ---------------------------------------------------------------------------
# Sentinel: universal-installer.sh lives at the flat root pre-migration.
if [[ ! -f "universal-installer.sh" ]]; then
  echo "ERROR: run this from the repo root (sentinel universal-installer.sh not found in \$PWD=$PWD)." >&2
  echo "       cd /Users/matrix/projects/dev/tools && ./migrate.sh" >&2
  exit 1
fi

# Must be inside a git work tree (git mv / git rm need it).
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not inside a git work tree." >&2
  exit 1
fi

echo "==> Guard passed. Reorganizing tools/ in $PWD"

# ---------------------------------------------------------------------------
# 2. Create directories and move files (git mv preserves history).
# ---------------------------------------------------------------------------

echo "==> shell-setup/"
mkdir -p shell-setup
git mv universal-installer.sh        shell-setup/universal-installer.sh
git mv bash-enhance-setup.sh         shell-setup/bash-enhance-setup.sh
git mv enable-starship-zsh.sh        shell-setup/enable-starship-zsh.sh
git mv fix-starship-two-lines.sh     shell-setup/fix-starship-two-lines.sh
git mv fix-terminal-startup.sh       shell-setup/fix-terminal-startup.sh

echo "==> net/"
mkdir -p net
git mv ssh_tunnel.sh                 net/ssh_tunnel.sh
git mv proxy7980.py                  net/proxy7980.py

echo "==> tts/"
mkdir -p tts
git mv paseo-edge-tts-bridge.mjs     tts/paseo-edge-tts-bridge.mjs

echo "==> vibe-kanban/"
mkdir -p vibe-kanban
git mv vibe-kanban-salvage.sh        vibe-kanban/vibe-kanban-salvage.sh

echo "==> codex-remote/ (moves as one \$SCRIPT_DIR-relative cluster)"
mkdir -p codex-remote
git mv codex-add-remote-server.sh                    codex-remote/codex-add-remote-server.sh
git mv codex-daemon-watchdog.sh                      codex-remote/codex-daemon-watchdog.sh
git mv codex-restart-daemons.sh                      codex-remote/codex-restart-daemons.sh
git mv codex-remote-start-daemon.sh                  codex-remote/codex-remote-start-daemon.sh
git mv codex-sync-remote-ssh-projects.mjs            codex-remote/codex-sync-remote-ssh-projects.mjs
git mv codex-remote-account-switch.sh                codex-remote/codex-remote-account-switch.sh
git mv codex-remote-hosts.txt                        codex-remote/codex-remote-hosts.txt
git mv codex-mobile-remote-tools.md                  codex-remote/codex-mobile-remote-tools.md
git mv codex-mobile-remote-control-troubleshooting.md codex-remote/codex-mobile-remote-control-troubleshooting.md
git mv codex-remote-account-switch.md                codex-remote/codex-remote-account-switch.md

# FROZEN (not moved): fix-codex-plugins.sh, codex-after-update-fix.sh, codex-patch/

# ---------------------------------------------------------------------------
# 3. Apply doc-snippet edits (AFTER the moves — files now live at NEW paths).
# ---------------------------------------------------------------------------
# These rewrite stale copy-paste absolute paths inside the relocated .md files.
# Runtime scripts resolve siblings via $SCRIPT_DIR, so only the documented
# absolute paths are stale; execution is unaffected.
#
# macOS/BSD sed in-place form is `sed -i ''`; GNU sed is `sed -i`. We auto-detect.
if sed --version >/dev/null 2>&1; then
  sed_inplace() { sed -i "$@"; }          # GNU sed
else
  sed_inplace() { sed -i '' "$@"; }       # BSD/macOS sed
fi

B="/Users/matrix/projects/dev/tools"   # old absolute prefix
RT="codex-remote/codex-mobile-remote-tools.md"
TS="codex-remote/codex-mobile-remote-control-troubleshooting.md"
AS="codex-remote/codex-remote-account-switch.md"

echo "==> doc edits: $RT (master runbook)"
# NOTE: do NOT rewrite frozen $B/fix-codex-plugins.sh, $B/codex-after-update-fix.sh,
# or $B/codex-patch/ references — those stay at root. Only the moved scripts below.
sed_inplace "s#${B}/codex-remote-hosts.txt#${B}/codex-remote/codex-remote-hosts.txt#g"                 "$RT"
sed_inplace "s#${B}/codex-add-remote-server.sh#${B}/codex-remote/codex-add-remote-server.sh#g"         "$RT"
sed_inplace "s#${B}/codex-restart-daemons.sh#${B}/codex-remote/codex-restart-daemons.sh#g"             "$RT"
sed_inplace "s#${B}/codex-remote-start-daemon.sh#${B}/codex-remote/codex-remote-start-daemon.sh#g"     "$RT"
sed_inplace "s#${B}/codex-sync-remote-ssh-projects.mjs#${B}/codex-remote/codex-sync-remote-ssh-projects.mjs#g" "$RT"
sed_inplace "s#${B}/codex-daemon-watchdog.sh#${B}/codex-remote/codex-daemon-watchdog.sh#g"             "$RT"
sed_inplace "s#${B}/ssh_tunnel.sh#${B}/net/ssh_tunnel.sh#g"                                            "$RT"

echo "==> doc edits: $TS"
sed_inplace "s#${B}/codex-remote-account-switch.sh#${B}/codex-remote/codex-remote-account-switch.sh#g" "$TS"

echo "==> doc edits: $AS"
sed_inplace "s#${B}/codex-remote-account-switch.sh#${B}/codex-remote/codex-remote-account-switch.sh#g" "$AS"

# ---------------------------------------------------------------------------
# 4. Append .gitignore rules for runtime/test artifacts.
# ---------------------------------------------------------------------------
echo "==> .gitignore"
cat >> .gitignore <<'EOF'

# --- added by migrate.sh ---
# Runtime/test artifacts (currently committed — untracked via git rm --cached below)
.paseo-edge-tts-bridge-test.mp3
.paseo-edge-tts-bridge-test.pcm
.paseo-edge-tts-bridge.log
.paseo-edge-tts-bridge.pid
.paseo-edge-tts-paseo-pcm-test.pcm
.paseo-edge-tts-test.mp3

# Generic patterns so regenerated artifacts stay ignored
.paseo-edge-tts-*
*.pcm
*.mp3
*.log
*.pid

# vibe-kanban salvage outputs (ROOT_DIR-derived)
.vk-home/
.vk-home-migrated/
EOF

# ---------------------------------------------------------------------------
# 5. Untrack the 6 already-committed artifacts (keeps them on disk).
# ---------------------------------------------------------------------------
# --ignore-unmatch so the script is idempotent if any are already gone.
echo "==> git rm --cached (untrack committed artifacts, keep working copies)"
git rm --cached --ignore-unmatch \
  .paseo-edge-tts-bridge-test.mp3 \
  .paseo-edge-tts-bridge-test.pcm \
  .paseo-edge-tts-bridge.log \
  .paseo-edge-tts-bridge.pid \
  .paseo-edge-tts-paseo-pcm-test.pcm \
  .paseo-edge-tts-test.mp3

# ---------------------------------------------------------------------------
# Done. Manual follow-ups below are NOT automated.
# ---------------------------------------------------------------------------
cat <<'EOF'

==> migrate.sh finished. Review `git status` / `git diff --cached`, then commit on a branch.

MANUAL follow-ups (see reorg-proposal.md "安全迁移说明" / externalUpdates):
  HARD  ~/Library/LaunchAgents/com.matrix.ssh-tunnel.plist
          ProgramArguments .../tools/ssh_tunnel.sh -> .../tools/net/ssh_tunnel.sh, then reload.
  HARD  ~/Library/LaunchAgents/com.matrix.codex-daemon-watchdog.plist
          ProgramArguments .../tools/codex-daemon-watchdog.sh -> .../tools/codex-remote/codex-daemon-watchdog.sh, then reload.
          Reload: launchctl bootout gui/$(id -u)/<label> 2>/dev/null; launchctl bootstrap gui/$(id -u) <plist>
  SOFT  ~/.codex/rules/default.rules:27,32 — update paseo prefix_rule to tts/ cwd, or launch bridge from tts/.
  SOFT  vibe-kanban — invoke with ROOT_DIR=/Users/matrix/projects/dev to preserve the prior default.
EOF
