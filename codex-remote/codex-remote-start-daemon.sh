#!/usr/bin/env bash
# Start or restart the Codex app-server daemon on a remote Linux host.

set -euo pipefail

ACTION="${1:-start}"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
STOP_TIMEOUT_SECONDS="${CODEX_REMOTE_STOP_TIMEOUT_SECONDS:-10}"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

run_with_timeout() {
  local seconds="$1"
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
    return
  fi

  "$@"
}

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [start|restart|reenroll|status|stop]

Default:
  start
EOF
}

find_codex() {
  if [ -n "${CODEX_BIN:-}" ] && [ -x "$CODEX_BIN" ]; then
    printf '%s\n' "$CODEX_BIN"
    return 0
  fi

  if [ -x "$CODEX_HOME_DIR/packages/standalone/current/codex" ]; then
    printf '%s\n' "$CODEX_HOME_DIR/packages/standalone/current/codex"
    return 0
  fi

  if [ -x "$HOME/.local/bin/codex" ]; then
    printf '%s\n' "$HOME/.local/bin/codex"
    return 0
  fi

  command -v codex
}

stop_app_server_processes() {
  local proc pid cmd pids

  for proc in /proc/[0-9]*; do
    [ -r "$proc/cmdline" ] || continue
    pid="${proc##*/}"
    cmd="$(tr '\0' ' ' < "$proc/cmdline")"
    case "$cmd" in
      *"codex app-server --remote-control"*|*"codex app-server --listen unix://"*|*"codex app-server proxy"*|*"codex app-server daemon pid-update-loop"*)
        kill "$pid" 2>/dev/null || true
        pids="${pids:-} $pid"
        ;;
    esac
  done

  [ -n "${pids:-}" ] || return 0
  sleep 1
  for pid in $pids; do
    [ -r "/proc/$pid/cmdline" ] || continue
    cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline")"
    case "$cmd" in
      *"codex app-server --remote-control"*|*"codex app-server --listen unix://"*|*"codex app-server proxy"*|*"codex app-server daemon pid-update-loop"*)
        kill -9 "$pid" 2>/dev/null || true
        ;;
    esac
  done
}

normalize_proxy_env() {
  local proxy_url

  proxy_url="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}"
  [ -n "$proxy_url" ] || return 0

  export HTTP_PROXY="${HTTP_PROXY:-$proxy_url}"
  export HTTPS_PROXY="${HTTPS_PROXY:-$proxy_url}"
  export ALL_PROXY="${ALL_PROXY:-$proxy_url}"
  export http_proxy="${http_proxy:-$HTTP_PROXY}"
  export https_proxy="${https_proxy:-$HTTPS_PROXY}"
  export all_proxy="${all_proxy:-$ALL_PROXY}"
}

load_runtime_env() {
  if [ -r "$CODEX_HOME_DIR/gaccode.env" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$CODEX_HOME_DIR/gaccode.env"
    set +a
  fi

  if [ -z "${CODEX_API_KEY:-}" ] && [ -n "${GACCODE_API_KEY:-}" ]; then
    export CODEX_API_KEY="$GACCODE_API_KEY"
  fi

  if [ -r "$HOME/proxy_config.sh" ]; then
    # Needed on ali-server-zxw; harmless on hosts where proxy is unused.
    # shellcheck disable=SC1090
    . "$HOME/proxy_config.sh" on >/dev/null 2>&1 || true
  fi

  normalize_proxy_env
}

start_remote_control() {
  local codex_bin="$1"
  local out
  local args=(remote-control start --json)

  if [ -n "${CODEX_REMOTE_APP_SERVER_CLIENT_NAME:-}" ]; then
    args+=(-c "app_server.client_name=\"$CODEX_REMOTE_APP_SERVER_CLIENT_NAME\"")
  fi

  out="$("$codex_bin" "${args[@]}" 2>&1)" && {
    printf '%s\n' "$out"
    return 0
  }

  if printf '%s\n' "$out" | grep -q "app server is running but is not managed"; then
    warn "Unmanaged app-server is blocking remote-control; stopping it."
    stop_app_server_processes
    sleep 2
    "$codex_bin" "${args[@]}"
    return
  fi

  printf '%s\n' "$out" >&2
  return 1
}

show_status() {
  local codex_bin="$1"

  "$codex_bin" app-server daemon version

  if command -v sqlite3 >/dev/null 2>&1 && [ -r "$CODEX_HOME_DIR/state_5.sqlite" ]; then
    sqlite3 "$CODEX_HOME_DIR/state_5.sqlite" \
      "select environment_id || char(9) || server_name || char(9) || datetime(updated_at, 'unixepoch', 'localtime') from remote_control_enrollments order by updated_at desc limit 3;" \
      2>/dev/null || true
  fi

  if command -v ss >/dev/null 2>&1; then
    ss -tnp 2>/dev/null | grep codex | grep -E ':443|127\.0\.0\.1:7890|\[::1\]:7890' || true
  fi
}

clear_remote_enrollment() {
  local db="$CODEX_HOME_DIR/state_5.sqlite"
  local backup
  local server_name="${CODEX_REMOTE_SERVER_NAME:-}"
  local env_id="${CODEX_REMOTE_ENVIRONMENT_ID:-}"
  local server_sql
  local env_sql

  if [ -z "$server_name" ] && [ -z "$env_id" ]; then
    server_name="$(hostname 2>/dev/null || true)"
  fi

  if [ ! -r "$db" ]; then
    warn "No readable Codex state database at $db; skipping enrollment cleanup."
    return 0
  fi

  if ! command -v sqlite3 >/dev/null 2>&1; then
    warn "sqlite3 not found; cannot clear remote-control enrollment."
    return 1
  fi

  backup="$CODEX_HOME_DIR/state_5.sqlite.backup-before-reenroll-$(date '+%Y%m%d%H%M%S')"
  sqlite3 "$db" ".backup '$backup'" || return 1

  server_sql="'$(printf '%s' "$server_name" | sed "s/'/''/g")'"
  env_sql="'$(printf '%s' "$env_id" | sed "s/'/''/g")'"

  sqlite3 "$db" \
    "delete from remote_control_enrollments
      where ($server_sql != '' and server_name = $server_sql)
         or ($env_sql != '' and environment_id = $env_sql);"

  log "Cleared remote-control enrollment for server='${server_name:-unknown}' env='${env_id:-unknown}'. Backup: $backup"
}

main() {
  case "$ACTION" in
    start|restart|reenroll|status|stop)
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      warn "Unknown action: $ACTION"
      usage >&2
      exit 2
      ;;
  esac

  load_runtime_env

  local codex_bin
  codex_bin="$(find_codex)"
  log "Using codex: $codex_bin"

  case "$ACTION" in
    start)
      log "Starting Codex daemon with remote control..."
      start_remote_control "$codex_bin"
      show_status "$codex_bin"
      ;;
    restart)
      log "Restarting Codex daemon with remote control..."
      run_with_timeout "$STOP_TIMEOUT_SECONDS" "$codex_bin" remote-control stop >/dev/null 2>&1 || true
      run_with_timeout "$STOP_TIMEOUT_SECONDS" "$codex_bin" app-server daemon stop >/dev/null 2>&1 || true
      stop_app_server_processes
      sleep 2
      start_remote_control "$codex_bin"
      show_status "$codex_bin"
      ;;
    reenroll)
      log "Re-enrolling Codex remote control..."
      run_with_timeout "$STOP_TIMEOUT_SECONDS" "$codex_bin" remote-control stop >/dev/null 2>&1 || true
      run_with_timeout "$STOP_TIMEOUT_SECONDS" "$codex_bin" app-server daemon stop >/dev/null 2>&1 || true
      stop_app_server_processes
      clear_remote_enrollment
      sleep 2
      start_remote_control "$codex_bin"
      show_status "$codex_bin"
      ;;
    status)
      show_status "$codex_bin"
      ;;
    stop)
      log "Stopping Codex daemon..."
      run_with_timeout "$STOP_TIMEOUT_SECONDS" "$codex_bin" remote-control stop >/dev/null 2>&1 || true
      run_with_timeout "$STOP_TIMEOUT_SECONDS" "$codex_bin" app-server daemon stop || true
      stop_app_server_processes
      ;;
  esac
}

main
