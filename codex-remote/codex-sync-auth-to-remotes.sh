#!/usr/bin/env bash
# Copy this Mac's Codex ChatGPT login to remote Codex hosts and re-enroll them.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
AUTH_FILE="${CODEX_AUTH_FILE:-$CODEX_HOME_DIR/auth.json}"
REMOTE_START_SCRIPT="$SCRIPT_DIR/codex-remote-start-daemon.sh"
HOSTS_FILE="${CODEX_REMOTE_HOSTS_FILE:-$SCRIPT_DIR/codex-remote-hosts.txt}"
DEFAULT_HOSTS="bwg-server-zxw ali-server-zxw"
FILE_HOSTS="$(awk 'NF && $1 !~ /^#/ { print $1 }' "$HOSTS_FILE" 2>/dev/null | xargs 2>/dev/null || true)"
HOSTS="${CODEX_REMOTE_HOSTS:-${FILE_HOSTS:-$DEFAULT_HOSTS}}"
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-12}"
SSH_RETRIES="${SSH_RETRIES:-3}"
REMOTE_INSTALL_TIMEOUT_SECONDS="${CODEX_REMOTE_INSTALL_TIMEOUT_SECONDS:-180}"
CLOUD_PROXY_URL="${CODEX_REMOTE_HTTP_PROXY:-http://127.0.0.1:7890}"
USE_PROXY=1
VALIDATE_CLOUD=1
REENROLL=1
HOSTS_FROM_ARGS=0
INSTALL_MISSING=1
REVERSE_PROXY_ON_INSTALL=1
REVERSE_PROXY_REMOTE_PORT="${CODEX_REMOTE_REVERSE_PROXY_PORT:-7890}"
REVERSE_PROXY_LOCAL_HOST="${CODEX_REMOTE_REVERSE_PROXY_LOCAL_HOST:-127.0.0.1}"
REVERSE_PROXY_LOCAL_PORT="${CODEX_REMOTE_REVERSE_PROXY_LOCAL_PORT:-7890}"
REVERSE_PROXY_SOCKS=""

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

validate_install_timeout() {
  case "$REMOTE_INSTALL_TIMEOUT_SECONDS" in
    ""|*[!0-9]*)
      die "--install-timeout must be a positive integer"
      ;;
  esac
  [ "$REMOTE_INSTALL_TIMEOUT_SECONDS" -gt 0 ] || die "--install-timeout must be greater than 0"
}

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME [options]

Options:
  --hosts "h1 h2"         Remote SSH aliases to sync. Default: "$HOSTS"
  --host h                Add one remote SSH alias. Can be used multiple times.
  --hosts-file PATH       Read remote SSH aliases from a file.
  --auth-file PATH        Local auth file. Default: "$AUTH_FILE"
  --http-proxy URL        Proxy for local cloud auth validation. Default: "$CLOUD_PROXY_URL"
  --no-proxy              Do not use a proxy for local cloud auth validation.
  --skip-cloud-check      Copy auth without checking the token against ChatGPT first.
  --no-reenroll           Copy auth only; do not re-enroll remote daemons.
  --no-install            Fail if Codex is missing on a remote host.
  --no-reverse-proxy      Do not open a temporary reverse proxy if install fails.
  --install-timeout SEC   Remote Codex install timeout before retrying. Default: $REMOTE_INSTALL_TIMEOUT_SECONDS
  -h, --help              Show this help.

Examples:
  $SCRIPT_NAME
  $SCRIPT_NAME --host bwg-server-zxw
EOF
}

add_host() {
  if [ "$HOSTS_FROM_ARGS" -eq 0 ]; then
    HOSTS=""
    HOSTS_FROM_ARGS=1
  fi

  if [ -z "$HOSTS" ]; then
    HOSTS="$1"
  else
    HOSTS="$HOSTS $1"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --hosts)
      [ "$#" -ge 2 ] || die "--hosts requires a value"
      HOSTS="$2"
      shift 2
      ;;
    --host)
      [ "$#" -ge 2 ] || die "--host requires a value"
      add_host "$2"
      shift 2
      ;;
    --hosts-file)
      [ "$#" -ge 2 ] || die "--hosts-file requires a value"
      HOSTS_FILE="$2"
      HOSTS="$(awk 'NF && $1 !~ /^#/ { print $1 }' "$HOSTS_FILE" 2>/dev/null | xargs 2>/dev/null || true)"
      [ -n "$HOSTS" ] || die "No hosts found in $HOSTS_FILE"
      shift 2
      ;;
    --auth-file)
      [ "$#" -ge 2 ] || die "--auth-file requires a path"
      AUTH_FILE="$2"
      shift 2
      ;;
    --http-proxy)
      [ "$#" -ge 2 ] || die "--http-proxy requires a URL"
      CLOUD_PROXY_URL="$2"
      USE_PROXY=1
      shift 2
      ;;
    --no-proxy)
      USE_PROXY=0
      shift
      ;;
    --skip-cloud-check)
      VALIDATE_CLOUD=0
      shift
      ;;
    --no-reenroll)
      REENROLL=0
      shift
      ;;
    --no-install)
      INSTALL_MISSING=0
      shift
      ;;
    --no-reverse-proxy)
      REVERSE_PROXY_ON_INSTALL=0
      shift
      ;;
    --install-timeout)
      [ "$#" -ge 2 ] || die "--install-timeout requires seconds"
      case "$2" in
        ""|*[!0-9]*)
          die "--install-timeout must be a positive integer"
          ;;
      esac
      [ "$2" -gt 0 ] || die "--install-timeout must be greater than 0"
      REMOTE_INSTALL_TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "Unknown option: $1"
      ;;
  esac
done

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

require_local_auth() {
  [ -r "$AUTH_FILE" ] || die "Local auth file is not readable: $AUTH_FILE"
  command -v jq >/dev/null 2>&1 || die "Missing required command: jq"

  local auth_mode
  local token
  auth_mode="$(jq -r '.auth_mode // empty' "$AUTH_FILE" 2>/dev/null)"
  token="$(jq -r '.tokens.access_token // empty' "$AUTH_FILE" 2>/dev/null)"

  [ "$auth_mode" = "chatgpt" ] || die "Local auth is not ChatGPT auth_mode; run codex login first."
  [ -n "$token" ] && [ "$token" != "null" ] || die "No access token found in $AUTH_FILE; run codex login first."
}

validate_local_cloud_auth() {
  [ "$VALIDATE_CLOUD" -eq 1 ] || {
    warn "Skipping local cloud auth validation by request."
    return 0
  }

  command -v curl >/dev/null 2>&1 || die "Missing required command: curl"

  local token
  local tmp
  local code
  local curl_status

  token="$(jq -r '.tokens.access_token // empty' "$AUTH_FILE" 2>/dev/null)"
  tmp="$(mktemp "${TMPDIR:-/tmp}/codex-auth-check.XXXXXX")" || die "Cannot create temp file."

  local curl_args=(-sS --connect-timeout 12 --max-time 30 -o "$tmp" -w '%{http_code}')
  if [ "$USE_PROXY" -eq 1 ]; then
    curl_args+=(-x "$CLOUD_PROXY_URL")
  fi

  code="$(
    curl "${curl_args[@]}" \
      -H "Authorization: Bearer $token" \
      'https://chatgpt.com/backend-api/codex/remote/control/environments?limit=1' 2>/dev/null
  )"
  curl_status=$?

  if [ "$curl_status" -ne 0 ]; then
    rm -f "$tmp"
    die "Could not reach ChatGPT remote-control API; re-run with --skip-cloud-check only if you are sure the local login is fresh."
  fi

  if [ "$code" = "200" ]; then
    rm -f "$tmp"
    log "Local ChatGPT auth is accepted by the remote-control API."
    return 0
  fi

  if [ "$code" = "401" ] && grep -q '"code"[[:space:]]*:[[:space:]]*"token_invalidated"' "$tmp"; then
    rm -f "$tmp"
    die "Local ChatGPT token is invalidated. Run codex-remote-account-switch.sh switch before syncing remotes."
  fi

  warn "ChatGPT remote-control API returned HTTP $code:"
  head -c 500 "$tmp" | sed 's/[[:cntrl:]]/ /g' >&2 || true
  printf '\n' >&2
  rm -f "$tmp"
  die "Local cloud auth validation failed."
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

    [ "$status" -eq 255 ] || return "$status"
    [ "$attempt" -lt "$SSH_RETRIES" ] || return "$status"

    sleep "$((attempt * 2))"
    attempt=$((attempt + 1))
  done

  return "$status"
}

scp_base() {
  local status=0
  local attempt=1

  while [ "$attempt" -le "$SSH_RETRIES" ]; do
    scp \
      -o BatchMode=yes \
      -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
      -o ConnectionAttempts=2 \
      "$@"
    status=$?

    [ "$status" -eq 255 ] || return "$status"
    [ "$attempt" -lt "$SSH_RETRIES" ] || return "$status"

    sleep "$((attempt * 2))"
    attempt=$((attempt + 1))
  done

  return "$status"
}

cleanup_reverse_proxies() {
  local entry
  local host
  local sock

  for entry in $REVERSE_PROXY_SOCKS; do
    host="${entry%%:*}"
    sock="${entry#*:}"
    [ -n "$host" ] && [ -n "$sock" ] || continue
    ssh -S "$sock" -O exit "$host" >/dev/null 2>&1 || true
    rm -f "$sock"
  done
}

remote_has_codex() {
  local host="$1"

  ssh_base "$host" '
    [ -x "$HOME/.codex/packages/standalone/current/codex" ] ||
    [ -x "$HOME/.local/bin/codex" ] ||
    command -v codex >/dev/null 2>&1
  ' >/dev/null 2>&1
}

copy_remote_helper() {
  local host="$1"

  [ -r "$REMOTE_START_SCRIPT" ] || die "Missing remote daemon helper: $REMOTE_START_SCRIPT"
  log "$host: installing remote daemon helper."
  scp_base "$REMOTE_START_SCRIPT" "$host:~/start-codex-daemon.sh" >/dev/null || return
  ssh_base "$host" 'chmod +x "$HOME/start-codex-daemon.sh"' || return
}

remote_install_codex() {
  local host="$1"
  local use_remote_proxy="$2"
  local proxy_prefix=""
  local install_timeout

  if [ "$use_remote_proxy" -eq 1 ]; then
    proxy_prefix="HTTP_PROXY=http://127.0.0.1:$REVERSE_PROXY_REMOTE_PORT HTTPS_PROXY=http://127.0.0.1:$REVERSE_PROXY_REMOTE_PORT http_proxy=http://127.0.0.1:$REVERSE_PROXY_REMOTE_PORT https_proxy=http://127.0.0.1:$REVERSE_PROXY_REMOTE_PORT npm_config_proxy=http://127.0.0.1:$REVERSE_PROXY_REMOTE_PORT npm_config_https_proxy=http://127.0.0.1:$REVERSE_PROXY_REMOTE_PORT"
  fi

  install_timeout="$(shell_quote "$REMOTE_INSTALL_TIMEOUT_SECONDS")"
  ssh \
    -o BatchMode=yes \
    -o ClearAllForwardings=yes \
    -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
    -o ConnectionAttempts=2 \
    "$host" "$proxy_prefix CODEX_REMOTE_INSTALL_TIMEOUT_SECONDS=$install_timeout bash -s" <<'REMOTE_INSTALL'
set -euo pipefail

mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"
export PATH="$HOME/.local/bin:$PATH"

if [ -x "$HOME/.codex/packages/standalone/current/codex" ] ||
   [ -x "$HOME/.local/bin/codex" ] ||
   command -v codex >/dev/null 2>&1; then
  exit 0
fi

run_install() {
  local install_pid
  local elapsed=0
  local timeout_seconds="${CODEX_REMOTE_INSTALL_TIMEOUT_SECONDS:-180}"

  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_seconds" "$@"
  else
    "$@" &
    install_pid=$!

    while kill -0 "$install_pid" 2>/dev/null; do
      if [ "$elapsed" -ge "$timeout_seconds" ]; then
        kill "$install_pid" 2>/dev/null || true
        sleep 2
        kill -9 "$install_pid" 2>/dev/null || true
        wait "$install_pid" 2>/dev/null || true
        return 124
      fi

      sleep 1
      elapsed=$((elapsed + 1))
    done

    wait "$install_pid"
  fi
}

if command -v npm >/dev/null 2>&1; then
  npm config set prefix "$HOME/.local" >/dev/null
  run_install npm install -g @openai/codex
elif command -v pnpm >/dev/null 2>&1; then
  export PNPM_HOME="$HOME/.local"
  run_install pnpm add -g @openai/codex
elif command -v bun >/dev/null 2>&1; then
  export BUN_INSTALL="$HOME/.local"
  run_install bun add -g @openai/codex
elif command -v yarn >/dev/null 2>&1; then
  yarn global dir >/dev/null 2>&1 || true
  run_install yarn global add @openai/codex
else
  echo "No supported JS package manager found. Install npm/pnpm/bun/yarn or Codex manually." >&2
  exit 127
fi

if [ -x "$HOME/.codex/packages/standalone/current/codex" ]; then
  "$HOME/.codex/packages/standalone/current/codex" --version
elif [ -x "$HOME/.local/bin/codex" ]; then
  "$HOME/.local/bin/codex" --version
else
  codex --version
fi
REMOTE_INSTALL
}

start_reverse_proxy() {
  local host="$1"
  local safe_host
  local sock

  safe_host="$(printf '%s' "$host" | sed 's/[^A-Za-z0-9_.-]/_/g')"
  sock="${TMPDIR:-/tmp}/codex-reverse-proxy-${safe_host}-$$.sock"

  log "$host: opening temporary reverse proxy 127.0.0.1:$REVERSE_PROXY_REMOTE_PORT -> $REVERSE_PROXY_LOCAL_HOST:$REVERSE_PROXY_LOCAL_PORT."
  ssh \
    -M \
    -S "$sock" \
    -fN \
    -o BatchMode=yes \
    -o ClearAllForwardings=yes \
    -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
    -o ExitOnForwardFailure=yes \
    -R "127.0.0.1:$REVERSE_PROXY_REMOTE_PORT:$REVERSE_PROXY_LOCAL_HOST:$REVERSE_PROXY_LOCAL_PORT" \
    "$host"

  REVERSE_PROXY_SOCKS="${REVERSE_PROXY_SOCKS:-} $host:$sock"
}

ensure_remote_codex() {
  local host="$1"

  copy_remote_helper "$host" || return

  if remote_has_codex "$host"; then
    log "$host: Codex is already installed."
    return 0
  fi
  local codex_status=$?
  if [ "$codex_status" -eq 255 ]; then
    warn "$host: SSH transport failed while checking Codex installation."
    return "$codex_status"
  fi

  [ "$INSTALL_MISSING" -eq 1 ] || die "$host: Codex is missing and --no-install was used."

  log "$host: Codex is missing; installing with remote package manager."
  if remote_install_codex "$host" 0; then
    return 0
  fi

  [ "$REVERSE_PROXY_ON_INSTALL" -eq 1 ] || die "$host: Codex install failed and reverse proxy fallback is disabled."

  warn "$host: direct Codex install failed; retrying through a temporary reverse proxy."
  start_reverse_proxy "$host"
  remote_install_codex "$host" 1
}

sync_host() {
  local host="$1"
  local remote_tmp=".codex/auth.json.sync-$(date '+%Y%m%d%H%M%S')-$$"
  local quoted_host

  log "$host: preparing ~/.codex."
  ssh_base "$host" 'mkdir -p "$HOME/.codex" && chmod 700 "$HOME/.codex"' || return

  ensure_remote_codex "$host" || return

  log "$host: copying auth.json."
  scp_base "$AUTH_FILE" "$host:$remote_tmp" >/dev/null || return

  log "$host: installing auth.json with backup."
  ssh_base "$host" "set -e
    if [ -f \"\$HOME/.codex/auth.json\" ]; then
      command cp -p \"\$HOME/.codex/auth.json\" \"\$HOME/.codex/auth.json.backup-before-sync-\$(date '+%Y%m%d%H%M%S')\"
    fi
    command mv -f \"\$HOME/$remote_tmp\" \"\$HOME/.codex/auth.json\"
    command chmod 600 \"\$HOME/.codex/auth.json\"
  " || return

  log "$host: login status."
  ssh_base "$host" 'if [ -x "$HOME/.codex/packages/standalone/current/codex" ]; then
      "$HOME/.codex/packages/standalone/current/codex" login status
    else
      codex login status
    fi' || return

  [ "$REENROLL" -eq 1 ] || return 0

  quoted_host="$(shell_quote "$host")"
  log "$host: re-enrolling remote-control daemon."
  ssh_base "$host" "CODEX_REMOTE_SERVER_NAME=$quoted_host \"\$HOME/start-codex-daemon.sh\" reenroll" || return
}

main() {
  trap cleanup_reverse_proxies EXIT INT TERM

  [ -n "$HOSTS" ] || die "No remote hosts configured."
  validate_install_timeout

  require_local_auth
  validate_local_cloud_auth

  local status=0
  local host
  for host in $HOSTS; do
    if ! sync_host "$host"; then
      warn "$host sync failed."
      status=1
    fi
  done

  exit "$status"
}

main
