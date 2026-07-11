#!/usr/bin/env bash
# Restart Codex remote-control daemons on this Mac and known SSH hosts.

set -u

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_BIN="${CODEX_BIN:-codex}"
CODEX_APP="${CODEX_APP:-/Applications/Codex.app}"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
HTTP_PROXY_VALUE="${CODEX_REMOTE_HTTP_PROXY:-http://127.0.0.1:7890}"
HTTPS_PROXY_VALUE="${CODEX_REMOTE_HTTPS_PROXY:-$HTTP_PROXY_VALUE}"
ALL_PROXY_VALUE="${CODEX_REMOTE_ALL_PROXY:-socks5h://127.0.0.1:7890}"
LOCAL=1
REMOTE=1
VERIFY=1
RELAUNCH_DESKTOP=0
HOSTS_FILE="${CODEX_REMOTE_HOSTS_FILE:-$SCRIPT_DIR/codex-remote-hosts.txt}"
DEFAULT_HOSTS="bwg-server-zxw ali-server-zxw"
FILE_HOSTS="$(awk 'NF && $1 !~ /^#/ { print $1 }' "$HOSTS_FILE" 2>/dev/null | xargs 2>/dev/null || true)"
HOSTS="${CODEX_REMOTE_HOSTS:-${FILE_HOSTS:-$DEFAULT_HOSTS}}"
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-12}"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME [options]

Options:
  --local-only          Restart only this Mac's managed Codex daemon.
  --remote-only         Restart only remote SSH host daemons.
  --hosts "h1 h2"       Remote SSH aliases to restart.
                         Default: "$HOSTS"
  --hosts-file PATH     Read remote SSH aliases from a file.
                         Default: "$HOSTS_FILE"
  --host h              Add one remote SSH alias. Can be used multiple times.
  --no-verify           Skip daemon and TCP connection checks after restart.
  --relaunch-desktop    Quit and reopen Codex.app after daemon restart.
  -h, --help            Show this help.

Examples:
  $SCRIPT_NAME
  $SCRIPT_NAME --hosts "bwg-server-zxw"
  $SCRIPT_NAME --local-only --relaunch-desktop
EOF
}

add_host() {
  if [ -z "$HOSTS" ]; then
    HOSTS="$1"
  else
    HOSTS="$HOSTS $1"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --local-only)
      LOCAL=1
      REMOTE=0
      shift
      ;;
    --remote-only)
      LOCAL=0
      REMOTE=1
      shift
      ;;
    --hosts)
      [ "$#" -ge 2 ] || { warn "--hosts requires a value"; exit 2; }
      HOSTS="$2"
      shift 2
      ;;
    --hosts-file)
      [ "$#" -ge 2 ] || { warn "--hosts-file requires a value"; exit 2; }
      HOSTS_FILE="$2"
      HOSTS="$(awk 'NF && $1 !~ /^#/ { print $1 }' "$HOSTS_FILE" 2>/dev/null | xargs 2>/dev/null || true)"
      [ -n "$HOSTS" ] || { warn "No hosts found in $HOSTS_FILE"; exit 2; }
      shift 2
      ;;
    --host)
      [ "$#" -ge 2 ] || { warn "--host requires a value"; exit 2; }
      add_host "$2"
      shift 2
      ;;
    --no-verify)
      VERIFY=0
      shift
      ;;
    --relaunch-desktop)
      RELAUNCH_DESKTOP=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      warn "Unknown option: $1"
      usage >&2
      exit 2
      ;;
  esac
done

STATUS=0

run_step() {
  "$@"
  local code=$?
  if [ "$code" -ne 0 ]; then
    STATUS=1
  fi
  return "$code"
}

codex_env() {
  local gaccode_key=""
  if [ -r "$CODEX_HOME_DIR/gaccode.env" ]; then
    gaccode_key="$(sed -n -E 's/^(CODEX_API_KEY|GACCODE_API_KEY)=//p' "$CODEX_HOME_DIR/gaccode.env" | head -n 1)"
  fi

  env -u OPENAI_API_KEY -u CODEX_API_KEY \
    GACCODE_API_KEY="$gaccode_key" \
    HTTP_PROXY="$HTTP_PROXY_VALUE" \
    HTTPS_PROXY="$HTTPS_PROXY_VALUE" \
    ALL_PROXY="$ALL_PROXY_VALUE" \
    "$CODEX_BIN" "$@"
}

restart_local_daemon() {
  if ! command -v "$CODEX_BIN" >/dev/null 2>&1; then
    warn "Local codex command not found: $CODEX_BIN"
    return 1
  fi

  log "Restarting local Codex daemon..."
  if ! codex_env app-server daemon restart; then
    warn "Local restart failed; trying start."
    codex_env app-server daemon start || return 1
  fi

  if [ "$VERIFY" -eq 1 ]; then
    log "Local daemon status:"
    codex_env app-server daemon version || return 1

    local pid
    pid="$(pgrep -f 'codex(\.real)? app-server --remote-control' | head -n 1 || true)"
    if [ -n "$pid" ] && command -v lsof >/dev/null 2>&1; then
      log "Local daemon TCP connections:"
      lsof -nP -p "$pid" -iTCP 2>/dev/null | awk 'NR == 1 || /:443|127\.0\.0\.1:7890/' || true
    fi
  fi
}

relaunch_desktop() {
  [ "$(uname -s)" = "Darwin" ] || return 0

  log "Relaunching Codex.app..."
  osascript -e 'quit app "Codex"' >/dev/null 2>&1 || true
  sleep 1
  open "$CODEX_APP" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    pgrep -f "$CODEX_APP/Contents/MacOS/Codex" >/dev/null 2>&1 && return 0
    sleep 1
  done

  warn "LaunchServices did not start Codex.app; launching app binary directly."
  nohup "$CODEX_APP/Contents/MacOS/Codex" >/tmp/codex-desktop-launch.log 2>&1 &
}

remote_script='
set -u

if [ -x "$HOME/start-codex-daemon.sh" ]; then
  exec "$HOME/start-codex-daemon.sh" restart
fi

codex_bin=""
if [ -x "$HOME/.codex/packages/standalone/current/codex" ]; then
  codex_bin="$HOME/.codex/packages/standalone/current/codex"
elif command -v codex >/dev/null 2>&1; then
  codex_bin="$(command -v codex)"
else
  echo "codex command not found" >&2
  exit 127
fi

if [ -r "$HOME/.codex/gaccode.env" ]; then
  set -a
  . "$HOME/.codex/gaccode.env"
  set +a
fi

if [ -z "${CODEX_API_KEY:-}" ] && [ -n "${GACCODE_API_KEY:-}" ]; then
  export CODEX_API_KEY="$GACCODE_API_KEY"
fi

if [ -r "$HOME/proxy_config.sh" ]; then
  . "$HOME/proxy_config.sh" on >/dev/null 2>&1 || true
fi

echo "codex: $codex_bin"
"$codex_bin" app-server daemon restart || "$codex_bin" app-server daemon start
"$codex_bin" app-server daemon version

if command -v sqlite3 >/dev/null 2>&1 && [ -r "$HOME/.codex/state_5.sqlite" ]; then
  sqlite3 "$HOME/.codex/state_5.sqlite" "select environment_id || char(9) || server_name || char(9) || datetime(updated_at, '\''unixepoch'\'', '\''localtime'\'') from remote_control_enrollments order by updated_at desc limit 3;" 2>/dev/null || true
fi

if command -v ss >/dev/null 2>&1; then
  ss -tnp 2>/dev/null | grep codex | grep -E ":443|127\.0\.0\.1:7890|\[::1\]:7890" || true
fi
'

restart_remote_daemon() {
  local host="$1"
  if [ -z "$host" ]; then
    return 0
  fi

  log "Restarting remote Codex daemon on $host..."
  ssh \
    -o BatchMode=yes \
    -o ClearAllForwardings=yes \
    -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
    "$host" "$remote_script"
}

main() {
  if [ "$LOCAL" -eq 1 ]; then
    run_step restart_local_daemon || warn "Local daemon restart had errors."
  fi

  if [ "$RELAUNCH_DESKTOP" -eq 1 ]; then
    run_step relaunch_desktop || warn "Codex.app relaunch had errors."
  fi

  if [ "$REMOTE" -eq 1 ]; then
    local host
    for host in $HOSTS; do
      run_step restart_remote_daemon "$host" || warn "Remote daemon restart failed on $host."
    done
  fi

  if [ "$STATUS" -eq 0 ]; then
    log "Done."
  else
    warn "Done with errors. Check the warnings above."
  fi
  exit "$STATUS"
}

main
