#!/usr/bin/env bash
# Add one SSH alias to Codex Desktop/mobile remote control.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_FILE="${CODEX_REMOTE_HOSTS_FILE:-$SCRIPT_DIR/codex-remote-hosts.txt}"
REMOTE_START_SCRIPT="$SCRIPT_DIR/codex-remote-start-daemon.sh"
SYNC_SCRIPT="$SCRIPT_DIR/codex-sync-remote-ssh-projects.mjs"
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-12}"

ALIAS=""
DISPLAY_NAME=""
DO_COPY=1
DO_START=1
DO_APPLY=1
DO_KICK_WATCHDOG=1
PROJECTS=()

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$(date '+%H:%M:%S')" "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME <ssh-alias> [remote-project-path ...]

Options:
  --name NAME          Display name in Codex App. Default: ssh alias.
  --hosts-file PATH    Host list used by restart/watchdog scripts.
                       Default: $HOSTS_FILE
  --no-copy            Do not copy /home/<user>/start-codex-daemon.sh.
  --no-start           Do not restart the remote daemon.
  --no-apply           Do not ask Codex.app to apply config.
  --no-watchdog-kick   Do not kick the watchdog after adding.
  -h, --help           Show this help.

Examples:
  $SCRIPT_NAME new-server-zxw
  $SCRIPT_NAME new-server-zxw /home/zxw/project1 /home/zxw/project2

Prerequisites:
  1. The SSH alias must already exist in ~/.ssh/config.
  2. SSH key login must work without a password prompt.
  3. If Codex CLI is missing, run:
       codex-remote-account-switch.sh sync-remotes --host <ssh-alias>
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name)
      [ "$#" -ge 2 ] || die "--name requires a value"
      DISPLAY_NAME="$2"
      shift 2
      ;;
    --hosts-file)
      [ "$#" -ge 2 ] || die "--hosts-file requires a value"
      HOSTS_FILE="$2"
      shift 2
      ;;
    --no-copy)
      DO_COPY=0
      shift
      ;;
    --no-start)
      DO_START=0
      shift
      ;;
    --no-apply)
      DO_APPLY=0
      shift
      ;;
    --no-watchdog-kick)
      DO_KICK_WATCHDOG=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      if [ -z "$ALIAS" ]; then
        ALIAS="$1"
      else
        PROJECTS+=("$1")
      fi
      shift
      ;;
  esac
done

while [ "$#" -gt 0 ]; do
  PROJECTS+=("$1")
  shift
done

[ -n "$ALIAS" ] || {
  usage >&2
  exit 2
}
[ -n "$DISPLAY_NAME" ] || DISPLAY_NAME="$ALIAS"

SSH_ARGS=(
  -o BatchMode=yes
  -o ClearAllForwardings=yes
  -o ConnectTimeout="$SSH_CONNECT_TIMEOUT"
)

require_file() {
  [ -e "$1" ] || die "Missing required file: $1"
}

remote_shell() {
  ssh "${SSH_ARGS[@]}" "$ALIAS" "$@"
}

append_host() {
  mkdir -p "$(dirname "$HOSTS_FILE")"
  touch "$HOSTS_FILE"

  if awk 'NF && $1 !~ /^#/ { print $1 }' "$HOSTS_FILE" | grep -Fxq "$ALIAS"; then
    log "$ALIAS already exists in $HOSTS_FILE"
    return
  fi

  printf '%s\n' "$ALIAS" >> "$HOSTS_FILE"
  log "Added $ALIAS to $HOSTS_FILE"
}

update_codex_state() {
  local remote_home="$1"
  node - "$ALIAS" "$DISPLAY_NAME" "$remote_home" "${PROJECTS[@]}" <<'NODE'
const { existsSync, mkdirSync, readFileSync, writeFileSync } = require("node:fs");
const { dirname, join, posix } = require("node:path");
const { homedir } = require("node:os");
const { randomUUID } = require("node:crypto");

const [, , alias, displayName, remoteHome, ...projectArgs] = process.argv;
const codexHome = process.env.CODEX_HOME || join(homedir(), ".codex");
const statePath = join(codexHome, ".codex-global-state.json");

function readJson(path, fallback) {
  if (!existsSync(path)) return fallback;
  return JSON.parse(readFileSync(path, "utf8"));
}

function normalizeRemotePath(value) {
  const trimmed = String(value || "").trim();
  if (!trimmed) return "";
  return trimmed.replace(/\/+$/, "") || trimmed;
}

function labelFor(path, fallback) {
  const base = posix.basename(normalizeRemotePath(path));
  return base && base !== "/" ? base : fallback;
}

function addProject(projects, project) {
  const remotePath = normalizeRemotePath(project.remotePath);
  if (!remotePath) return;
  if (projects.some((item) => normalizeRemotePath(item.remotePath) === remotePath)) return;
  projects.push({
    id: randomUUID(),
    hostId: project.hostId,
    remotePath,
    label: project.label,
  });
}

const state = readJson(statePath, {});
const managedKey = "codex-managed-remote-connections";
const projectsKey = "remote-projects";
state[managedKey] = Array.isArray(state[managedKey]) ? state[managedKey] : [];
state[projectsKey] = Array.isArray(state[projectsKey]) ? state[projectsKey] : [];

let connection = state[managedKey].find((item) => item.alias === alias);
const hostId = connection?.hostId || `remote-ssh-discovered:${alias}`;
if (!connection) {
  connection = {
    hostId,
    connectionAnalyticsId: randomUUID(),
    displayName,
    source: "discovered",
    alias,
    hostname: null,
    sshPort: null,
    identity: null,
  };
  state[managedKey].push(connection);
} else {
  connection.displayName = connection.displayName || displayName;
}

addProject(state[projectsKey], {
  hostId,
  remotePath: remoteHome,
  label: displayName,
});

for (const projectPath of projectArgs) {
  addProject(state[projectsKey], {
    hostId,
    remotePath: projectPath,
    label: labelFor(projectPath, displayName),
  });
}

mkdirSync(dirname(statePath), { recursive: true });
writeFileSync(statePath, `${JSON.stringify(state, null, 2)}\n`);
console.log(`Updated ${statePath}`);
console.log(`Managed remote: ${alias}`);
console.log(`Projects: ${[remoteHome, ...projectArgs].map(normalizeRemotePath).filter(Boolean).join(", ")}`);
NODE
}

kick_watchdog() {
  [ "$(uname -s)" = "Darwin" ] || return 0
  launchctl print "gui/$(id -u)/com.matrix.codex-daemon-watchdog" >/dev/null 2>&1 || return 0
  launchctl kickstart -k "gui/$(id -u)/com.matrix.codex-daemon-watchdog" >/dev/null 2>&1 || true
}

main() {
  require_file "$SYNC_SCRIPT"
  if [ "$DO_COPY" -eq 1 ]; then
    require_file "$REMOTE_START_SCRIPT"
  fi

  log "Checking SSH alias: $ALIAS"
  ssh -G "$ALIAS" >/dev/null

  local remote_home remote_user remote_host
  remote_home="$(remote_shell 'printf "%s" "$HOME"')"
  remote_user="$(remote_shell 'whoami')"
  remote_host="$(remote_shell 'hostname')"
  [ -n "$remote_home" ] || die "Could not detect remote HOME for $ALIAS"
  log "Remote target: $remote_user@$remote_host:$remote_home"

  append_host

  if [ "$DO_COPY" -eq 1 ]; then
    log "Installing remote daemon helper to $ALIAS:$remote_home/start-codex-daemon.sh"
    scp "${SSH_ARGS[@]}" "$REMOTE_START_SCRIPT" "$ALIAS:$remote_home/start-codex-daemon.sh" >/dev/null
    remote_shell 'chmod +x "$HOME/start-codex-daemon.sh"'
  fi

  if [ "$DO_START" -eq 1 ]; then
    log "Restarting remote Codex daemon on $ALIAS"
    remote_shell '$HOME/start-codex-daemon.sh restart'
  fi

  log "Updating Codex Desktop remote project state"
  update_codex_state "$remote_home"

  if [ "$DO_APPLY" -eq 1 ]; then
    log "Applying Codex.app remote config"
    node "$SYNC_SCRIPT" --apply
  else
    node "$SYNC_SCRIPT"
  fi

  if [ "$DO_KICK_WATCHDOG" -eq 1 ]; then
    kick_watchdog
  fi

  log "Done. If the phone list is open already, refresh/reopen it after a short delay."
}

main
