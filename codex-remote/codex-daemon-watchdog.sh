#!/usr/bin/env bash
# Lightweight watchdog for Codex remote-control daemons.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESTART_SCRIPT="${RESTART_SCRIPT:-$SCRIPT_DIR/codex-restart-daemons.sh}"
SYNC_AUTH_SCRIPT="${SYNC_AUTH_SCRIPT:-$SCRIPT_DIR/codex-sync-auth-to-remotes.sh}"
CODE_SIGN_CLONE_CLEANUP_SCRIPT="${CODE_SIGN_CLONE_CLEANUP_SCRIPT:-$SCRIPT_DIR/codex-clean-code-sign-clones.sh}"
CODEX_BIN="${CODEX_BIN:-codex}"
HOSTS_FILE="${CODEX_REMOTE_HOSTS_FILE:-$SCRIPT_DIR/codex-remote-hosts.txt}"
DEFAULT_HOSTS="bwg-server-zxw ali-server-zxw"
FILE_HOSTS="$(awk 'NF && $1 !~ /^#/ { print $1 }' "$HOSTS_FILE" 2>/dev/null | xargs 2>/dev/null || true)"
HOSTS="${CODEX_WATCHDOG_HOSTS:-${FILE_HOSTS:-$DEFAULT_HOSTS}}"
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-12}"
SSH_RETRIES="${SSH_RETRIES:-3}"
LOCK_DIR="${TMPDIR:-/tmp}/codex-daemon-watchdog.lock"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CLOUD_PROXY_URL="${CODEX_WATCHDOG_HTTP_PROXY:-http://127.0.0.1:7890}"
USE_CLOUD_PROXY="${CODEX_WATCHDOG_USE_PROXY:-1}"
PROXY_TEST_URL="${CODEX_WATCHDOG_PROXY_TEST_URL:-https://chatgpt.com/backend-api/codex/remote/control/environments?limit=1}"
PROXY_RESTART_CMD="${CODEX_WATCHDOG_PROXY_RESTART_CMD:-}"
LOCAL_ALL_PROXY_URL="${CODEX_WATCHDOG_ALL_PROXY:-socks5h://127.0.0.1:7890}"
CLASH_CONTROLLER_SOCKET="${CODEX_WATCHDOG_CLASH_CONTROLLER_SOCKET:-/tmp/verge/verge-mihomo.sock}"
CODEX_APP_NAME="${CODEX_APP_NAME:-Codex}"
CODEX_APP_PATH="${CODEX_APP_PATH:-/Applications/Codex.app}"
LOCAL_DISPLAY_NAME="${CODEX_WATCHDOG_LOCAL_DISPLAY_NAME:-mac-mini}"
MANAGE_LOCAL_DAEMON="${CODEX_WATCHDOG_MANAGE_LOCAL_DAEMON:-0}"
AUTO_SYNC_REMOTE_AUTH="${CODEX_WATCHDOG_AUTO_SYNC_REMOTE_AUTH:-1}"
TUNNEL_LABEL="${CODEX_TUNNEL_LABEL:-com.matrix.ssh-tunnel}"
TUNNEL_PLIST="${CODEX_TUNNEL_PLIST:-$HOME/Library/LaunchAgents/com.matrix.ssh-tunnel.plist}"
CLOUD_ENV_JSON=""
CLOUD_ENV_READY=0
CLOUD_AUTH_INVALID=0

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

ssh_base() {
  local status=0
  local attempt=1

  while [ "$attempt" -le "$SSH_RETRIES" ]; do
    ssh \
      -o BatchMode=yes \
      -o ClearAllForwardings=yes \
      -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
      -o ConnectionAttempts=2 \
      "$@"
    status=$?

    # 255 is the OpenSSH transport error used for transient resets/timeouts.
    [ "$status" -eq 255 ] || return "$status"
    [ "$attempt" -lt "$SSH_RETRIES" ] || return "$status"

    sleep "$((attempt * 2))"
    attempt=$((attempt + 1))
  done

  return "$status"
}

acquire_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log "Another watchdog run is still active; skipping."
    exit 0
  fi
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM
}

load_local_runtime_env() {
  local env_file="$CODEX_HOME_DIR/gaccode.env"
  local gaccode_key

  if [ -r "$env_file" ] && [ -z "${GACCODE_API_KEY:-}" ]; then
    gaccode_key="$(sed -n -E 's/^(CODEX_API_KEY|GACCODE_API_KEY)=//p' "$env_file" | head -n 1)"
    [ -z "$gaccode_key" ] || export GACCODE_API_KEY="$gaccode_key"
  fi

  unset OPENAI_API_KEY
  unset CODEX_API_KEY

  if [ "$USE_CLOUD_PROXY" -eq 1 ]; then
    export HTTP_PROXY="${HTTP_PROXY:-$CLOUD_PROXY_URL}"
    export HTTPS_PROXY="${HTTPS_PROXY:-$CLOUD_PROXY_URL}"
    export ALL_PROXY="${ALL_PROXY:-$LOCAL_ALL_PROXY_URL}"
    export http_proxy="${http_proxy:-$HTTP_PROXY}"
    export https_proxy="${https_proxy:-$HTTPS_PROXY}"
    export all_proxy="${all_proxy:-$ALL_PROXY}"
  fi
}

local_healthy() {
  command -v "$CODEX_BIN" >/dev/null 2>&1 || return 1

  local out
  out="$("$CODEX_BIN" app-server daemon version 2>&1)" || {
    warn "Local daemon status failed: $out"
    return 1
  }

  printf '%s\n' "$out" | grep -q '"status":"running"'
}

local_remote_control_pids() {
  pgrep -f 'codex(\.real)? app-server --remote-control'
}

local_remote_control_has_proxy_env() {
  [ "$USE_CLOUD_PROXY" -eq 1 ] || return 0

  local pids
  local pid
  pids="$(local_remote_control_pids || true)"
  [ -n "$pids" ] || return 1

  for pid in $pids; do
    ps eww -p "$pid" 2>/dev/null | grep -Eq '(^| )(HTTP_PROXY|HTTPS_PROXY|ALL_PROXY)=' || return 1
  done
}

local_remote_control_recently_failed() {
  local logs_db="$CODEX_HOME_DIR/logs_2.sqlite"
  [ -r "$logs_db" ] || return 1
  command -v sqlite3 >/dev/null 2>&1 || return 1

  sqlite3 "$logs_db" "
    with recent as (
      select
        max(case
          when target = 'codex_app_server_transport::transport::remote_control::websocket'
            and (
              feedback_log_body like 'failed to connect to app-server remote control websocket%'
              or feedback_log_body like '%timed out connecting to remote control websocket%'
            )
          then ts end) as last_failed,
        max(case
          when target = 'log'
            and feedback_log_body like 'Sending frame:%remoteControl/status/changed%status%connected%'
          then ts end) as last_connected
      from logs
      where ts >= strftime('%s','now','-10 minutes')
    )
    select case
      when coalesce(last_failed, 0) > coalesce(last_connected, 0) then 1
      else 0
    end
    from recent;
  " 2>/dev/null | grep -q 1
}

fix_local() {
  if [ ! -x "$RESTART_SCRIPT" ]; then
    warn "Restart script is not executable: $RESTART_SCRIPT"
    return 1
  fi

  log "Local daemon unhealthy; restarting local daemon."
  "$RESTART_SCRIPT" --local-only --no-verify
}

cleanup_code_sign_clones() {
  [ "$(uname -s)" = "Darwin" ] || return 0
  [ -x "$CODE_SIGN_CLONE_CLEANUP_SCRIPT" ] || return 0

  "$CODE_SIGN_CLONE_CLEANUP_SCRIPT" --quiet || warn "Codex code-sign clone cleanup failed."
}

stop_local_daemon_if_running() {
  local pids

  pids="$(local_remote_control_pids || true)"
  [ -n "$pids" ] || return 0

  log "Stopping local standalone Codex daemon; Codex Desktop owns $LOCAL_DISPLAY_NAME remote control."
  "$CODEX_BIN" app-server daemon stop >/dev/null 2>&1 || warn "Local standalone daemon stop failed."
}

fix_desktop() {
  [ "$(uname -s)" = "Darwin" ] || return 0

  log "$LOCAL_DISPLAY_NAME cloud environment unhealthy; relaunching Codex Desktop."
  osascript -e "quit app \"$CODEX_APP_NAME\"" >/dev/null 2>&1 || true
  sleep 2
  open -a "$CODEX_APP_NAME" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    pgrep -f "$CODEX_APP_PATH/Contents/MacOS/Codex" >/dev/null 2>&1 && return 0
    sleep 1
  done

  warn "LaunchServices did not start Codex Desktop; launching app binary directly."
  nohup "$CODEX_APP_PATH/Contents/MacOS/Codex" >/tmp/codex-desktop-launch.log 2>&1 &
}

remote_status() {
  local host="$1"
  ssh_base "$host" '$HOME/start-codex-daemon.sh status'
}

remote_healthy() {
  local host="$1"
  local output="$2"

  printf '%s\n' "$output" | grep -q '"status":"running"' || return 1

  if host_needs_proxy_tunnel "$host"; then
    printf '%s\n' "$output" | grep -Eq '^ESTAB .*127\.0\.0\.1:7890|^ESTAB .*\[::1\]:7890'
    return
  fi

  printf '%s\n' "$output" | grep -Eq '^ESTAB .*(:443|127\.0\.0\.1:7890|\[::1\]:7890)'
}

remote_environment_id() {
  local output="$1"
  printf '%s\n' "$output" | awk '/^env_e_/ { print $1; exit }'
}

load_cloud_environments() {
  local auth_file="$CODEX_HOME_DIR/auth.json"
  local token
  local tmp
  local code
  local curl_status

  CLOUD_ENV_READY=0
  CLOUD_ENV_JSON=""
  CLOUD_AUTH_INVALID=0

  command -v curl >/dev/null 2>&1 || {
    warn "curl not found; skipping cloud online check."
    return 1
  }
  command -v jq >/dev/null 2>&1 || {
    warn "jq not found; skipping cloud online check."
    return 1
  }
  [ -r "$auth_file" ] || {
    warn "No readable auth file at $auth_file; skipping cloud online check."
    return 1
  }

  token="$(jq -r '.tokens.access_token // empty' "$auth_file" 2>/dev/null)"
  if [ -z "$token" ] || [ "$token" = "null" ]; then
    warn "No access token in $auth_file; skipping cloud online check."
    return 1
  fi

  tmp="$(mktemp "${TMPDIR:-/tmp}/codex-cloud-env.XXXXXX")" || {
    warn "Cannot create temp file; skipping cloud online check."
    return 1
  }

  local curl_args=(-sS --connect-timeout 20 --max-time 40 -o "$tmp" -w '%{http_code}')
  if [ "$USE_CLOUD_PROXY" -eq 1 ]; then
    curl_args+=(-x "$CLOUD_PROXY_URL")
  fi

  code="$(
    curl "${curl_args[@]}" \
      -H "Authorization: Bearer $token" \
      'https://chatgpt.com/backend-api/codex/remote/control/environments?limit=100' 2>/dev/null
  )"
  curl_status=$?
  CLOUD_ENV_JSON="$(cat "$tmp" 2>/dev/null || true)"
  rm -f "$tmp"

  if [ "$curl_status" -ne 0 ]; then
    warn "Cloud environment check failed; keeping local/TCP watchdog only for this run."
    return 1
  fi

  if [ "$code" = "401" ] && printf '%s\n' "$CLOUD_ENV_JSON" | grep -q '"code"[[:space:]]*:[[:space:]]*"token_invalidated"'; then
    CLOUD_AUTH_INVALID=1
    warn "Cloud environment check failed: Codex ChatGPT authentication token was invalidated; re-login is required."
    return 1
  fi

  if [ "$code" != "200" ]; then
    warn "Cloud environment check failed with HTTP $code; keeping local/TCP watchdog only for this run."
    return 1
  fi

  CLOUD_ENV_READY=1
}

http_proxy_healthy() {
  local proxy_url="$1"
  local code
  local i

  for i in 1 2; do
    code="$(
      curl -sS -o /dev/null -w '%{http_code}' \
        --connect-timeout 10 \
        --max-time 20 \
        -x "$proxy_url" \
        "$PROXY_TEST_URL" 2>/dev/null
    )" || return 1

    case "$code" in
      [234][0-9][0-9])
        ;;
      *)
        return 1
        ;;
    esac
  done

  return 0
}

local_proxy_healthy() {
  [ "$USE_CLOUD_PROXY" -eq 1 ] || return 0
  command -v curl >/dev/null 2>&1 || return 1

  http_proxy_healthy "$CLOUD_PROXY_URL"
}

switch_first_healthy_clash_proxy() {
  [ -S "$CLASH_CONTROLLER_SOCKET" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  local controller="http://127.0.0.1"
  local current
  local name

  current="$(
    curl -sS --unix-socket "$CLASH_CONTROLLER_SOCKET" "$controller/proxies" 2>/dev/null |
      jq -r '.proxies.GLOBAL.now // empty'
  )"

  while IFS= read -r name; do
    case "$name" in
      ""|DIRECT|REJECT|REJECT-DROP|PASS|COMPATIBLE)
        continue
        ;;
    esac

    [ "$name" != "$current" ] || continue
    log "Testing Clash GLOBAL proxy: $name"
    jq -n --arg name "$name" '{name: $name}' |
      curl -sS --unix-socket "$CLASH_CONTROLLER_SOCKET" \
        -H 'Content-Type: application/json' \
        -X PUT \
        --data-binary @- \
        "$controller/proxies/GLOBAL" >/dev/null || continue

    curl -sS --unix-socket "$CLASH_CONTROLLER_SOCKET" -X DELETE "$controller/connections" >/dev/null 2>&1 || true
    sleep 1

    if local_proxy_healthy; then
      log "Selected healthy Clash GLOBAL proxy: $name"
      return 0
    fi
  done < <(
    curl -sS --unix-socket "$CLASH_CONTROLLER_SOCKET" "$controller/proxies" 2>/dev/null |
      jq -r '.proxies.GLOBAL.all[]? // empty'
  )

  return 1
}

repair_local_proxy() {
  [ "$USE_CLOUD_PROXY" -eq 1 ] || return 0

  if local_proxy_healthy; then
    log "Local proxy healthy."
    return 0
  fi

  warn "Local proxy $CLOUD_PROXY_URL cannot reach $PROXY_TEST_URL."

  if [ -n "$PROXY_RESTART_CMD" ]; then
    log "Running configured proxy restart command."
    sh -c "$PROXY_RESTART_CMD" || warn "Configured proxy restart command failed."
    sleep 5
  elif switch_first_healthy_clash_proxy; then
    return 0
  elif [ "$(uname -s)" = "Darwin" ]; then
    log "Opening Clash Verge to restore the local proxy if it is stopped."
    open -a "Clash Verge" >/dev/null 2>&1 || true
    sleep 5
  fi

  if local_proxy_healthy; then
    log "Local proxy repaired."
    return 0
  fi

  warn "Local proxy is still unavailable; remote hosts that depend on it may stay offline until the VPN/proxy is reconnected."
  return 1
}

cloud_env_online() {
  local env_id="$1"

  [ "$CLOUD_ENV_READY" -eq 1 ] || return 0
  [ -n "$env_id" ] || return 1

  printf '%s\n' "$CLOUD_ENV_JSON" |
    jq -e --arg id "$env_id" '.items[]? | select(.env_id == $id or .id == $id or .environment_id == $id) | select(.online == true)' >/dev/null && return 0

  cloud_env_online_direct "$env_id"
}

cloud_env_online_direct() {
  local env_id="$1"
  local auth_file="$CODEX_HOME_DIR/auth.json"
  local token

  [ "$CLOUD_ENV_READY" -eq 1 ] || return 0
  [ -n "$env_id" ] || return 1

  token="$(jq -r '.tokens.access_token // empty' "$auth_file" 2>/dev/null)"
  [ -n "$token" ] && [ "$token" != "null" ] || return 1

  local curl_args=(-fsS --connect-timeout 20 --max-time 40)
  if [ "$USE_CLOUD_PROXY" -eq 1 ]; then
    curl_args+=(-x "$CLOUD_PROXY_URL")
  fi

  curl "${curl_args[@]}" \
    -H "Authorization: Bearer $token" \
    "https://chatgpt.com/backend-api/codex/remote/control/environments/$env_id" 2>/dev/null |
    jq -e '.online == true' >/dev/null
}

cloud_env_named_online() {
  local name="$1"

  [ "$CLOUD_ENV_READY" -eq 1 ] || return 0
  [ -n "$name" ] || return 1

  printf '%s\n' "$CLOUD_ENV_JSON" |
    jq -e --arg name "$name" '.items[]? | select((.display_name // .name // "") == $name) | select(.online == true)' >/dev/null
}

cloud_env_display_name() {
  local env_id="$1"

  [ "$CLOUD_ENV_READY" -eq 1 ] || return 1
  [ -n "$env_id" ] || return 1

  printf '%s\n' "$CLOUD_ENV_JSON" |
    jq -r --arg id "$env_id" '.items[]? | select(.env_id == $id or .id == $id or .environment_id == $id) | .display_name // .name // empty' |
    head -n 1
}

fix_cloud_env_name() {
  local host="$1"
  local env_id="$2"
  local current_name
  local auth_file="$CODEX_HOME_DIR/auth.json"
  local token

  [ "$CLOUD_ENV_READY" -eq 1 ] || return 0
  [ -n "$env_id" ] || return 0

  current_name="$(cloud_env_display_name "$env_id" 2>/dev/null || true)"
  [ -n "$current_name" ] || return 0
  [ "$current_name" != "$host" ] || return 0

  token="$(jq -r '.tokens.access_token // empty' "$auth_file" 2>/dev/null)"
  [ -n "$token" ] && [ "$token" != "null" ] || return 1

  local curl_args=(-fsS --connect-timeout 20 --max-time 40)
  if [ "$USE_CLOUD_PROXY" -eq 1 ]; then
    curl_args+=(-x "$CLOUD_PROXY_URL")
  fi

  log "$host cloud display name is '$current_name'; renaming to '$host'."
  jq -n --arg name "$host" '{name: $name}' |
    curl "${curl_args[@]}" \
      -X PATCH \
      -H "Authorization: Bearer $token" \
      -H 'Content-Type: application/json' \
      --data-binary @- \
      "https://chatgpt.com/backend-api/codex/remote/control/environments/$env_id" >/dev/null
}

host_needs_proxy_tunnel() {
  case "$1" in
    ali-server-zxw|123.56.64.5)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

remote_proxy_healthy() {
  local host="$1"

  ssh_base "$host" 'if command -v curl >/dev/null 2>&1; then
      code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 20 -x http://127.0.0.1:7890 "https://chatgpt.com/backend-api/codex/remote/control/environments?limit=1" 2>/dev/null)" || exit 1
      case "$code" in [234][0-9][0-9]) exit 0 ;; *) exit 1 ;; esac
    fi
    command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 7890' >/dev/null 2>&1
}

restart_proxy_tunnel() {
  if command -v launchctl >/dev/null 2>&1 && [ -f "$TUNNEL_PLIST" ]; then
    launchctl kickstart -k "gui/$(id -u)/$TUNNEL_LABEL" >/dev/null 2>&1 ||
      launchctl bootstrap "gui/$(id -u)" "$TUNNEL_PLIST" >/dev/null 2>&1 || return 1
    sleep 5
    return 0
  fi

  warn "Cannot restart SSH tunnel: launchctl or $TUNNEL_PLIST unavailable."
  return 1
}

ensure_remote_prerequisites() {
  local host
  for host in $HOSTS; do
    host_needs_proxy_tunnel "$host" || continue

    if remote_proxy_healthy "$host"; then
      log "$host proxy tunnel healthy."
      continue
    fi

    warn "$host proxy tunnel is unavailable; restarting SSH tunnel."
    restart_proxy_tunnel || {
      warn "$host proxy tunnel restart failed."
      continue
    }

    if remote_proxy_healthy "$host"; then
      log "$host proxy tunnel repaired."
      refresh_local_desktop_proxy "$host"
    else
      warn "$host proxy tunnel is still unavailable after restart."
    fi
  done
}

fix_remote() {
  local host="$1"

  log "$host unhealthy; restarting remote daemon."
  ssh_base "$host" '$HOME/start-codex-daemon.sh restart'
}

remote_auth_invalidated() {
  local host="$1"
  local use_remote_proxy=0
  local output

  [ "$AUTO_SYNC_REMOTE_AUTH" -eq 1 ] || return 1
  [ "$CLOUD_ENV_READY" -eq 1 ] || return 1

  if host_needs_proxy_tunnel "$host"; then
    use_remote_proxy=1
  fi

  output="$(
    ssh \
      -o BatchMode=yes \
      -o ClearAllForwardings=yes \
      -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
      -o ConnectionAttempts=2 \
      "$host" "USE_REMOTE_PROXY=$use_remote_proxy bash -s" <<'REMOTE_AUTH_CHECK'
set -u

if [ -r "$HOME/proxy_config.sh" ]; then
  . "$HOME/proxy_config.sh" on >/dev/null 2>&1 || true
fi

if command -v jq >/dev/null 2>&1; then
  token="$(jq -r '.tokens.access_token // empty' "$HOME/.codex/auth.json" 2>/dev/null)"
else
  token="$(sed -n -E 's/.*"access_token"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$HOME/.codex/auth.json" 2>/dev/null | head -n 1)"
fi

[ -n "$token" ] && [ "$token" != "null" ] || exit 1

tmp="$(mktemp "${TMPDIR:-/tmp}/codex-remote-auth.XXXXXX")" || exit 1
curl_args=(-sS --connect-timeout 8 --max-time 20 -o "$tmp" -w '%{http_code}')
if [ "${USE_REMOTE_PROXY:-0}" -eq 1 ]; then
  curl_args+=(-x http://127.0.0.1:7890)
fi

code="$(curl "${curl_args[@]}" \
  -H "Authorization: Bearer $token" \
  'https://chatgpt.com/backend-api/codex/remote/control/environments?limit=1' 2>/dev/null || true)"

if [ "$code" = "401" ] && grep -q '"code"[[:space:]]*:[[:space:]]*"token_invalidated"' "$tmp"; then
  rm -f "$tmp"
  printf 'token_invalidated\n'
  exit 0
fi

rm -f "$tmp"
exit 1
REMOTE_AUTH_CHECK
  )" || return 1

  [ "$output" = "token_invalidated" ]
}

remote_auth_refresh_failed() {
  local host="$1"

  [ "$AUTO_SYNC_REMOTE_AUTH" -eq 1 ] || return 1

  ssh_base "$host" '
    log_file="$HOME/.codex/app-server-daemon/app-server.stderr.log"
    if [ -r "$log_file" ] &&
       find "$log_file" -mmin -20 -print -quit 2>/dev/null | grep -q . &&
       tail -n 240 "$log_file" | grep -Eq "refresh_token_reused|refresh token was already used|Please log out and sign in again|token_invalidated|token_expired|Provided authentication token is expired|access token could not be refreshed"; then
      exit 0
    fi

    logs_db="$HOME/.codex/logs_2.sqlite"
    [ -r "$logs_db" ] || exit 1
    command -v sqlite3 >/dev/null 2>&1 || exit 1

    sqlite3 "$logs_db" "
      select 1
      from logs
      where ts >= strftime('\''%s'\'','\''now'\'','\''-20 minutes'\'')
        and (
          feedback_log_body like '\''%refresh_token_reused%'\''
          or feedback_log_body like '\''%refresh token was already used%'\''
          or feedback_log_body like '\''%Please log out and sign in again%'\''
          or feedback_log_body like '\''%token_invalidated%'\''
          or feedback_log_body like '\''%token_expired%'\''
          or feedback_log_body like '\''%Provided authentication token is expired%'\''
          or feedback_log_body like '\''%access token could not be refreshed%'\''
        )
      limit 1;
    " 2>/dev/null | grep -q 1
  ' >/dev/null 2>&1
}

remote_missing_prerequisites() {
  local host="$1"
  local status

  ssh_base "$host" '
      [ -x "$HOME/start-codex-daemon.sh" ] || exit 10
      [ -x "$HOME/.codex/packages/standalone/current/codex" ] ||
      [ -x "$HOME/.local/bin/codex" ] ||
      command -v codex >/dev/null 2>&1 || exit 11
    ' >/dev/null 2>&1
  status=$?

  case "$status" in
    10|11)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

sync_remote_auth_from_local() {
  local host="$1"
  local reason="${2:-remote ChatGPT token is invalidated}"

  [ "$AUTO_SYNC_REMOTE_AUTH" -eq 1 ] || return 1
  [ "$CLOUD_ENV_READY" -eq 1 ] || return 1

  if [ ! -x "$SYNC_AUTH_SCRIPT" ]; then
    warn "Remote auth sync script is not executable: $SYNC_AUTH_SCRIPT"
    return 1
  fi

  log "$host $reason; syncing local auth and re-enrolling."
  "$SYNC_AUTH_SCRIPT" --host "$host"
}

local_desktop_proxy_pids_for_host() {
  local host="$1"

  [ "$(uname -s)" = "Darwin" ] || return 0

  ps -axo pid=,comm=,command= 2>/dev/null |
    awk -v host="$host" '
      $2 == "ssh" &&
      index($0, host) &&
      index($0, "codex app-server proxy --sock") &&
      index($0, "desktop-ssh-websocket-v0.sock") {
        print $1
      }
    '
}

refresh_local_desktop_proxy() {
  local host="$1"
  local pids
  local pid

  pids="$(local_desktop_proxy_pids_for_host "$host" || true)"
  [ -n "$pids" ] || return 0

  log "$host remote was repaired; restarting local Codex Desktop SSH proxy for that host."
  for pid in $pids; do
    kill "$pid" 2>/dev/null || true
  done

  sleep 1

  for pid in $pids; do
    kill -0 "$pid" 2>/dev/null || continue
    kill -9 "$pid" 2>/dev/null || true
  done
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

fix_remote_reenroll() {
  local host="$1"
  local env_id="${2:-}"
  local quoted_host
  local quoted_env

  quoted_host="$(shell_quote "$host")"
  quoted_env="$(shell_quote "$env_id")"

  log "$host cloud environment is stale/offline; clearing enrollment and restarting remote daemon."
  ssh_base "$host" "CODEX_REMOTE_SERVER_NAME=$quoted_host CODEX_REMOTE_ENVIRONMENT_ID=$quoted_env \"\$HOME/start-codex-daemon.sh\" reenroll"
}

check_remote() {
  local host="$1"
  local out
  local env_id

  out="$(remote_status "$host" 2>&1)" || {
    warn "$host status check failed: $out"
    if remote_auth_refresh_failed "$host"; then
      if sync_remote_auth_from_local "$host" "has a reused/invalid refresh token"; then
        refresh_local_desktop_proxy "$host"
        return
      fi
      warn "$host remote auth sync failed; falling back to daemon restart."
    fi
    if remote_missing_prerequisites "$host"; then
      if sync_remote_auth_from_local "$host" "is missing Codex CLI or the remote daemon helper"; then
        refresh_local_desktop_proxy "$host"
        return
      fi
      warn "$host prerequisite sync failed; falling back to daemon restart."
    fi
    if remote_auth_invalidated "$host"; then
      if sync_remote_auth_from_local "$host"; then
        refresh_local_desktop_proxy "$host"
        return
      fi
      warn "$host remote auth sync failed; falling back to daemon restart."
    fi
    if fix_remote "$host"; then
      refresh_local_desktop_proxy "$host"
    fi
    return
  }

  if ! remote_healthy "$host" "$out"; then
    warn "$host daemon is running without an active Codex remote-control connection."
    if remote_auth_refresh_failed "$host"; then
      if sync_remote_auth_from_local "$host" "has a reused/invalid refresh token"; then
        refresh_local_desktop_proxy "$host"
        return
      fi
      warn "$host remote auth sync failed; falling back to daemon restart."
    fi
    if remote_auth_invalidated "$host"; then
      if sync_remote_auth_from_local "$host"; then
        refresh_local_desktop_proxy "$host"
        return
      fi
      warn "$host remote auth sync failed; falling back to daemon restart."
    fi
    if fix_remote "$host"; then
      refresh_local_desktop_proxy "$host"
    fi
    return
  fi

  env_id="$(remote_environment_id "$out")"
  fix_cloud_env_name "$host" "$env_id" || warn "$host cloud display-name repair failed."

  if cloud_env_online "$env_id"; then
    log "$host healthy."
    return 0
  fi

  warn "$host has a local daemon/TCP connection, but cloud does not show env '${env_id:-unknown}' online."
  if remote_auth_refresh_failed "$host"; then
    if sync_remote_auth_from_local "$host" "has a reused/invalid refresh token"; then
      refresh_local_desktop_proxy "$host"
      return
    fi
    warn "$host remote auth sync failed; falling back to re-enroll."
  fi
  if remote_auth_invalidated "$host"; then
    if sync_remote_auth_from_local "$host"; then
      refresh_local_desktop_proxy "$host"
      return
    fi
    warn "$host remote auth sync failed; falling back to re-enroll."
  fi

  if fix_remote_reenroll "$host" "$env_id"; then
    refresh_local_desktop_proxy "$host"
  fi
}

main() {
  acquire_lock
  load_local_runtime_env
  cleanup_code_sign_clones
  repair_local_proxy || true
  load_cloud_environments || true

  if [ "$MANAGE_LOCAL_DAEMON" -eq 1 ]; then
    if local_healthy && local_remote_control_has_proxy_env && ! local_remote_control_recently_failed; then
      log "Local Codex daemon healthy."
    else
      if ! local_healthy; then
        warn "Local Codex daemon is not running."
      elif ! local_remote_control_has_proxy_env; then
        warn "Local Codex remote-control daemon is missing proxy environment."
      else
        warn "Local Codex remote-control websocket has recent unrecovered failures."
        switch_first_healthy_clash_proxy || true
      fi
      fix_local || warn "Local daemon repair failed."
    fi
  else
    stop_local_daemon_if_running
  fi

  if [ "$CLOUD_AUTH_INVALID" -eq 1 ]; then
    warn "$LOCAL_DISPLAY_NAME cloud environment cannot be repaired by restart while Codex auth is invalidated."
    warn "Skipping remote daemon restarts until Codex is re-logged in."
    return 0
  fi

  if cloud_env_named_online "$LOCAL_DISPLAY_NAME"; then
    log "$LOCAL_DISPLAY_NAME cloud environment healthy."
  else
    warn "$LOCAL_DISPLAY_NAME cloud environment is offline."
    fix_desktop || warn "$LOCAL_DISPLAY_NAME desktop repair failed."
  fi

  ensure_remote_prerequisites

  local host
  for host in $HOSTS; do
    check_remote "$host" || warn "$host repair/check failed."
  done
}

main
