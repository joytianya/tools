#!/usr/bin/env bash
# Switch the ChatGPT account used by Codex Desktop mobile remote control.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_BIN="${CODEX_BIN:-codex}"
CODEX_APP_NAME="${CODEX_APP_NAME:-Codex}"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
HTTP_PROXY_VALUE="${HTTP_PROXY_VALUE:-http://127.0.0.1:7890}"
HTTPS_PROXY_VALUE="${HTTPS_PROXY_VALUE:-$HTTP_PROXY_VALUE}"
ALL_PROXY_VALUE="${ALL_PROXY_VALUE:-socks5h://127.0.0.1:7890}"
USE_PROXY=1
START_DAEMON=0
WAIT_SECONDS=8

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME switch [options]
  $SCRIPT_NAME status [options]
  $SCRIPT_NAME verify [options]
  $SCRIPT_NAME verify-model [options]
  $SCRIPT_NAME verify-phone-model [options]
  $SCRIPT_NAME verify-all [options]
  $SCRIPT_NAME watch-phone [options]
  $SCRIPT_NAME fix-desktop [options]
  $SCRIPT_NAME sync-remotes [sync options]
  $SCRIPT_NAME set-proxy [options]
  $SCRIPT_NAME unset-proxy
  $SCRIPT_NAME set-gaccode-key
  $SCRIPT_NAME unset-gaccode-key
  $SCRIPT_NAME update-gaccode-key
  $SCRIPT_NAME set-api-key
  $SCRIPT_NAME unset-api-key

Commands:
  switch      Stop Codex remote daemon, quit Desktop, logout, login, reopen Desktop.
  status      Show local Codex, proxy, process, login, and cloud environment status.
  verify      Check cloud online status and recent phone remote-control logs.
  verify-model Check CLI and Desktop app-server model calls through gaccode.
  verify-phone-model Check recent phone PHONE_OK threads for gaccode model calls.
  verify-all  Run all non-destructive remote/model/plugin local-state checks.
  watch-phone Watch for a phone remote request that reaches gaccode /responses.
  fix-desktop Clear GUI API-key env, keep proxy, and restart Codex Desktop cleanly.
  sync-remotes Copy local ChatGPT auth to remote hosts and re-enroll them.
  set-proxy   Set launchctl proxy variables for GUI apps.
  unset-proxy Remove launchctl proxy variables for GUI apps.
  set-gaccode-key Set launchctl GACCODE_API_KEY from ~/.codex/gaccode.env.
  unset-gaccode-key Remove launchctl GACCODE_API_KEY.
  update-gaccode-key Read a new gaccode key from stdin, save it, and update launchctl.
  set-api-key Set launchctl CODEX_API_KEY from the current shell.
  unset-api-key Remove launchctl CODEX_API_KEY and OPENAI_API_KEY.

Options:
  --no-proxy             Do not set or use proxy variables.
  --http-proxy URL       Default: $HTTP_PROXY_VALUE
  --https-proxy URL      Default: same as --http-proxy
  --all-proxy URL        Default: $ALL_PROXY_VALUE
  --start-daemon         Start codex remote-control daemon after login.
  --wait SECONDS         Wait after opening Codex Desktop. Default: $WAIT_SECONDS
  -h, --help             Show this help.

Examples:
  $SCRIPT_NAME switch
  $SCRIPT_NAME switch --http-proxy http://127.0.0.1:7890 --all-proxy socks5h://127.0.0.1:7890
  $SCRIPT_NAME status
  $SCRIPT_NAME verify
  $SCRIPT_NAME verify-model
  $SCRIPT_NAME verify-phone-model
  $SCRIPT_NAME verify-all
  $SCRIPT_NAME watch-phone --wait 120
  $SCRIPT_NAME fix-desktop
  $SCRIPT_NAME sync-remotes
  $SCRIPT_NAME sync-remotes --host bwg-server-zxw
  printf '%s\n' "\$NEW_GACCODE_KEY" | $SCRIPT_NAME update-gaccode-key
EOF
}

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

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_macos() {
  [ "$(uname -s)" = "Darwin" ] || die "This script expects macOS."
}

parse_options() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --no-proxy)
        USE_PROXY=0
        shift
        ;;
      --http-proxy)
        [ "$#" -ge 2 ] || die "--http-proxy requires a URL"
        HTTP_PROXY_VALUE="$2"
        HTTPS_PROXY_VALUE="$2"
        shift 2
        ;;
      --https-proxy)
        [ "$#" -ge 2 ] || die "--https-proxy requires a URL"
        HTTPS_PROXY_VALUE="$2"
        shift 2
        ;;
      --all-proxy)
        [ "$#" -ge 2 ] || die "--all-proxy requires a URL"
        ALL_PROXY_VALUE="$2"
        shift 2
        ;;
      --start-daemon)
        START_DAEMON=1
        shift
        ;;
      --wait)
        [ "$#" -ge 2 ] || die "--wait requires seconds"
        WAIT_SECONDS="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
}

codex_env() {
  local gaccode_key=""
  if [ -r "$CODEX_HOME_DIR/gaccode.env" ]; then
    gaccode_key="$(sed -n -E 's/^(CODEX_API_KEY|GACCODE_API_KEY)=//p' "$CODEX_HOME_DIR/gaccode.env" | head -n 1)"
  fi

  if [ "$USE_PROXY" -eq 1 ]; then
    env -u OPENAI_API_KEY -u CODEX_API_KEY \
      GACCODE_API_KEY="$gaccode_key" \
      HTTP_PROXY="$HTTP_PROXY_VALUE" \
      HTTPS_PROXY="$HTTPS_PROXY_VALUE" \
      ALL_PROXY="$ALL_PROXY_VALUE" \
      "$CODEX_BIN" "$@"
  else
    env -u OPENAI_API_KEY -u CODEX_API_KEY \
      GACCODE_API_KEY="$gaccode_key" \
      "$CODEX_BIN" "$@"
  fi
}

curl_env() {
  if [ "$USE_PROXY" -eq 1 ]; then
    curl -sS --connect-timeout 20 --max-time 40 -x "$HTTP_PROXY_VALUE" "$@"
  else
    curl -sS --connect-timeout 20 --max-time 40 "$@"
  fi
}

set_gui_proxy() {
  require_macos
  if [ "$USE_PROXY" -eq 0 ]; then
    log "Skipping launchctl proxy setup because --no-proxy was used."
    return
  fi

  log "Setting GUI proxy variables with launchctl."
  launchctl setenv HTTP_PROXY "$HTTP_PROXY_VALUE"
  launchctl setenv HTTPS_PROXY "$HTTPS_PROXY_VALUE"
  launchctl setenv ALL_PROXY "$ALL_PROXY_VALUE"
}

set_gui_api_key() {
  require_macos
  if [ -z "${CODEX_API_KEY:-}" ]; then
    die "CODEX_API_KEY is not set in this shell."
  fi

  log "Setting GUI CODEX_API_KEY with launchctl."
  launchctl setenv CODEX_API_KEY "$CODEX_API_KEY"
}

set_gui_gaccode_key() {
  require_macos

  local env_file="$CODEX_HOME_DIR/gaccode.env"
  local gaccode_key
  if [ ! -r "$env_file" ]; then
    die "Missing readable gaccode env file: $env_file"
  fi

  gaccode_key="$(sed -n -E 's/^(CODEX_API_KEY|GACCODE_API_KEY)=//p' "$env_file" | head -n 1)"
  if [ -z "$gaccode_key" ]; then
    die "No GACCODE_API_KEY value found in $env_file."
  fi

  log "Setting GUI GACCODE_API_KEY with launchctl."
  launchctl setenv GACCODE_API_KEY "$gaccode_key"
}

update_gaccode_key() {
  require_macos

  local gaccode_key
  if [ -t 0 ]; then
    printf 'Paste new gaccode key: ' >&2
  fi

  IFS= read -r gaccode_key || true
  if [ -z "$gaccode_key" ]; then
    die "No gaccode key was provided on stdin."
  fi

  umask 077
  mkdir -p "$CODEX_HOME_DIR"
  printf 'GACCODE_API_KEY=%s\n' "$gaccode_key" > "$CODEX_HOME_DIR/gaccode.env.tmp"
  mv "$CODEX_HOME_DIR/gaccode.env.tmp" "$CODEX_HOME_DIR/gaccode.env"
  chmod 600 "$CODEX_HOME_DIR/gaccode.env"

  set_gui_gaccode_key
  log "Updated $CODEX_HOME_DIR/gaccode.env."
}

unset_gui_gaccode_key() {
  require_macos
  log "Removing GUI GACCODE_API_KEY from launchctl."
  launchctl unsetenv GACCODE_API_KEY || true
}

unset_gui_api_key() {
  require_macos
  log "Removing GUI API-key variables from launchctl."
  launchctl unsetenv CODEX_API_KEY || true
  launchctl unsetenv OPENAI_API_KEY || true
}

unset_gui_proxy() {
  require_macos
  log "Removing GUI proxy variables from launchctl."
  launchctl unsetenv HTTP_PROXY || true
  launchctl unsetenv HTTPS_PROXY || true
  launchctl unsetenv ALL_PROXY || true
}

show_gui_proxy() {
  require_macos
  printf 'launchctl HTTP_PROXY=%s\n' "$(launchctl getenv HTTP_PROXY || true)"
  printf 'launchctl HTTPS_PROXY=%s\n' "$(launchctl getenv HTTPS_PROXY || true)"
  printf 'launchctl ALL_PROXY=%s\n' "$(launchctl getenv ALL_PROXY || true)"
}

show_gui_api_key_status() {
  require_macos
  if [ -n "$(launchctl getenv CODEX_API_KEY 2>/dev/null || true)" ]; then
    printf 'launchctl CODEX_API_KEY=set\n'
  else
    printf 'launchctl CODEX_API_KEY=missing\n'
  fi

  if [ -n "$(launchctl getenv OPENAI_API_KEY 2>/dev/null || true)" ]; then
    printf 'launchctl OPENAI_API_KEY=set\n'
  else
    printf 'launchctl OPENAI_API_KEY=missing\n'
  fi

  if [ -n "$(launchctl getenv GACCODE_API_KEY 2>/dev/null || true)" ]; then
    printf 'launchctl GACCODE_API_KEY=set\n'
  else
    printf 'launchctl GACCODE_API_KEY=missing\n'
  fi
}

quit_desktop() {
  require_macos
  log "Quitting Codex Desktop if it is running."
  osascript -e "tell application \"$CODEX_APP_NAME\" to quit" >/dev/null 2>&1 || true

  for _ in $(seq 1 20); do
    if ! pgrep -x "$CODEX_APP_NAME" >/dev/null 2>&1; then
      break
    fi
    sleep 0.5
  done

  if pgrep -x "$CODEX_APP_NAME" >/dev/null 2>&1; then
    warn "Codex Desktop still appears to be running. Close it manually if login behaves oddly."
  fi

  if pgrep -f 'Codex[.]app/Contents/Resources/codex app-server --analytics-default-enabled' >/dev/null 2>&1; then
    warn "Stopping stale Codex Desktop app-server."
    pkill -f 'Codex[.]app/Contents/Resources/codex app-server --analytics-default-enabled' || true
  fi
}

open_desktop() {
  require_macos
  log "Opening Codex Desktop with a clean launch environment."
  env -i \
    HOME="$HOME" \
    USER="$(id -un)" \
    LOGNAME="$(id -un)" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
    open -a "$CODEX_APP_NAME"
  sleep "$WAIT_SECONDS"
}

stop_remote_daemon() {
  log "Stopping codex remote-control daemon if it is running."
  codex_env remote-control stop >/dev/null 2>&1 || true
}

start_remote_daemon() {
  if [ "$START_DAEMON" -eq 0 ]; then
    return
  fi

  log "Starting codex remote-control daemon."
  codex_env remote-control start --json || true
}

show_versions() {
  printf 'System Codex CLI: '
  codex_env --version || true

  if [ -x /Applications/Codex.app/Contents/Resources/codex ]; then
    printf 'Desktop bundled CLI: '
    /Applications/Codex.app/Contents/Resources/codex --version || true
  fi
}

show_processes() {
  log "Codex-related processes:"
  ps -axo pid=,command= | rg 'Codex.app/Contents/MacOS/Codex|Codex.app/Contents/Resources/codex app-server --analytics-default-enabled|codex app-server --remote-control' | rg -v ' rg ' || true
}

show_desktop_app_server_env_status() {
  local pid
  pid="$(ps -axo pid=,command= | rg 'Codex.app/Contents/Resources/codex app-server --analytics-default-enabled' | rg -v ' rg ' | awk 'NR == 1 { print $1 }' || true)"
  if [ -z "$pid" ]; then
    warn "Codex Desktop app-server is not running."
    return 0
  fi

  if ps eww -p "$pid" | rg -q 'CODEX_API_KEY='; then
    printf 'Desktop app-server CODEX_API_KEY=set\n'
  else
    printf 'Desktop app-server CODEX_API_KEY=missing\n'
  fi

  if ps eww -p "$pid" | rg -q 'OPENAI_API_KEY='; then
    printf 'Desktop app-server OPENAI_API_KEY=set\n'
  else
    printf 'Desktop app-server OPENAI_API_KEY=missing\n'
  fi

  if ps eww -p "$pid" | rg -q 'GACCODE_API_KEY='; then
    printf 'Desktop app-server GACCODE_API_KEY=set\n'
  else
    printf 'Desktop app-server GACCODE_API_KEY=missing\n'
  fi
}

show_default_provider() {
  local config_file="$CODEX_HOME_DIR/config.toml"
  if [ ! -f "$config_file" ]; then
    warn "No config file found at $config_file."
    return 0
  fi

  log "Default model provider:"
  awk '
    /^model = / { print; next }
    /^model_provider = / { print; next }
    /^model_catalog_json = / { print; next }
    /^\[model_providers\./ { in_provider=1; print; next }
    /^\[/ && in_provider { in_provider=0; next }
    in_provider && /^(name|base_url|env_key|wire_api) = / { print }
  ' "$config_file"
}

show_login_status() {
  log "Codex login status:"
  codex_env login status || true
}

print_cloud_environments() {
  require_cmd curl
  require_cmd jq

  local auth_file="$CODEX_HOME_DIR/auth.json"
  if [ ! -f "$auth_file" ]; then
    warn "No auth file found at $auth_file. Login first."
    return 0
  fi

  local token
  token="$(jq -r '.tokens.access_token // empty' "$auth_file")"
  if [ -z "$token" ] || [ "$token" = "null" ]; then
    warn "No access token found in $auth_file. Login first."
    return 0
  fi

  log "Cloud remote-control environments:"
  curl_env \
    -H @<(printf 'Authorization: Bearer %s\n' "$token") \
    'https://chatgpt.com/backend-api/codex/remote/control/environments?limit=100' |
    jq '.items[]? | {
      display_name,
      client_name,
      client_type,
      online,
      busy,
      app_server_version,
      client_version,
      last_seen_at
    }'
}

print_recent_phone_logs() {
  require_cmd sqlite3

  local log_db="$CODEX_HOME_DIR/logs_2.sqlite"
  if [ ! -f "$log_db" ]; then
    warn "No logs DB found at $log_db."
    return 0
  fi

  log "Recent phone remote-control log evidence:"
  sqlite3 "$log_db" \
    'SELECT datetime(ts,"unixepoch"), level, target, substr(feedback_log_body,1,1000)
     FROM logs
     WHERE ts >= strftime("%s","now","-10 minutes")
       AND target LIKE "codex_app_server%"
       AND (
         feedback_log_body LIKE "%codex_chatgpt_ios_remote%"
         OR feedback_log_body LIKE "%remoteControl/status/changed%"
       )
       AND feedback_log_body NOT LIKE "%session_loop%"
     ORDER BY ts DESC
     LIMIT 80;' || true
}

watch_phone_model_request() {
  require_cmd sqlite3
  require_cmd rg

  local log_db="$CODEX_HOME_DIR/logs_2.sqlite"
  if [ ! -f "$log_db" ]; then
    die "No logs DB found at $log_db."
  fi

  local start_ts end_ts found_methods found_response model_errors phone_threads thread_id
  start_ts="$(date +%s)"
  end_ts=$((start_ts + WAIT_SECONDS))

  log "Watching phone remote-control logs for ${WAIT_SECONDS}s."
  log "On the phone, enter mac-mini and send exactly: PHONE_OK"

  while [ "$(date +%s)" -lt "$end_ts" ]; do
    found_response="$(
      sqlite3 "$log_db" \
        "SELECT datetime(ts,'unixepoch')
         FROM logs
         WHERE ts >= $start_ts
           AND feedback_log_body LIKE '%app_server.client_name=\"codex_chatgpt_ios_remote\"%'
           AND feedback_log_body LIKE '%POST to https://gaccode.com/codex/v1/responses%'
         ORDER BY ts DESC
         LIMIT 1;"
    )"
    if [ -n "$found_response" ]; then
      log "Phone model path verified at $found_response: codex_chatgpt_ios_remote -> gaccode /responses."
      return 0
    fi

    phone_threads="$(
      sqlite3 "$log_db" \
        "SELECT feedback_log_body
         FROM logs
         WHERE ts >= $start_ts
           AND feedback_log_body LIKE '%app_server.client_name=\"codex_chatgpt_ios_remote\"%';" |
        rg -o 'thread_id=[0-9a-f-]+|thread\.id=[0-9a-f-]+' |
        sed -E 's/^thread[_.]id=//' |
        sort -u || true
    )"

    for thread_id in $phone_threads; do
      found_response="$(
        sqlite3 "$log_db" \
          "SELECT datetime(ts,'unixepoch')
           FROM logs
           WHERE ts >= $start_ts
             AND feedback_log_body LIKE '%POST to https://gaccode.com/codex/v1/responses%'
             AND feedback_log_body LIKE '%model=gpt-5.5%'
             AND feedback_log_body LIKE '%codex.turn.reasoning_effort=xhigh%'
             AND (
               feedback_log_body LIKE '%thread_id=$thread_id%'
               OR feedback_log_body LIKE '%thread.id=$thread_id%'
             )
           ORDER BY ts DESC
           LIMIT 1;"
      )"
      if [ -n "$found_response" ]; then
        log "Phone model path verified at $found_response: iOS remote thread $thread_id -> gaccode /responses."
        return 0
      fi
    done
    sleep 2
  done

  log "Phone remote methods observed during the watch:"
  found_methods="$(
    sqlite3 "$log_db" \
      "SELECT feedback_log_body
       FROM logs
       WHERE ts >= $start_ts
         AND feedback_log_body LIKE '%app_server.client_name=\"codex_chatgpt_ios_remote\"%';" |
      rg -o 'rpc.method="[^"]+"' | sort | uniq -c || true
  )"
  if [ -n "$found_methods" ]; then
    printf '%s\n' "$found_methods"
  else
    printf '  none\n'
  fi

  model_errors="$(
    sqlite3 "$log_db" \
      "SELECT datetime(ts,'unixepoch') || ' ' || level || ' ' || target
       FROM logs
       WHERE ts >= $start_ts
         AND feedback_log_body LIKE '%app_server.client_name=\"codex_chatgpt_ios_remote\"%'
         AND (
           feedback_log_body LIKE '%missing field%models%'
           OR feedback_log_body LIKE '%Payment Required%'
           OR feedback_log_body LIKE '%Unauthorized%'
           OR feedback_log_body LIKE '%ERROR%'
         )
       ORDER BY ts DESC
       LIMIT 10;" || true
  )"
  if [ -n "$model_errors" ]; then
    warn "Phone-side model/plugin errors observed:"
    printf '%s\n' "$model_errors" >&2
  fi

  if [ -z "$found_methods" ]; then
    die "No phone remote-control request reached this Mac during the watch window."
  fi

  die "Phone reached this Mac, but no phone-triggered gaccode /responses request was observed."
}

verify_phone_model_request() {
  require_cmd sqlite3
  require_cmd rg

  local log_db="$CODEX_HOME_DIR/logs_2.sqlite"
  if [ ! -f "$log_db" ]; then
    die "No logs DB found at $log_db."
  fi

  local since_ts expected_model phone_threads thread_id phone_seen_ts input_seen_ts response_seen_ts
  local best_thread="" best_phone_ts="" best_input_ts="" best_response_ts=""
  since_ts=$(( $(date +%s) - 3600 ))
  expected_model="$(awk -F= '
    /^\[/ { in_table=1 }
    !in_table && $1 ~ /^[[:space:]]*model[[:space:]]*$/ {
      gsub(/[[:space:]\"]/, "", $2)
      print $2
      exit
    }
  ' "$CODEX_HOME_DIR/config.toml" 2>/dev/null || true)"
  expected_model="${expected_model:-gpt-5.5}"

  phone_threads="$(
    sqlite3 "$log_db" \
      "SELECT feedback_log_body
       FROM logs
       WHERE ts >= $since_ts
         AND feedback_log_body LIKE 'app_server.request%'
         AND feedback_log_body LIKE '%app_server.client_name=\"codex_chatgpt_ios_remote\"%';" |
      rg -o 'thread_id=[0-9a-f-]+|thread\.id=[0-9a-f-]+' |
      sed -E 's/^thread[_.]id=//' |
      sort -u || true
  )"

  if [ -z "$phone_threads" ]; then
    die "No phone remote-control thread reached this Mac in the last 60 minutes."
  fi

  for thread_id in $phone_threads; do
    input_seen_ts="$(
      sqlite3 "$log_db" \
        "SELECT ts
         FROM logs
         WHERE ts >= $since_ts
           AND feedback_log_body LIKE 'session_loop{thread_id=$thread_id}:%'
           AND (
             feedback_log_body LIKE '%thread_id=$thread_id%'
             OR feedback_log_body LIKE '%thread.id=$thread_id%'
           )
           AND feedback_log_body LIKE '%Submission sub=Submission%'
           AND feedback_log_body LIKE '%op: UserInput%'
           AND feedback_log_body LIKE '%PHONE_OK%'
         ORDER BY ts DESC
         LIMIT 1;"
    )"
    if [ -z "$input_seen_ts" ]; then
      continue
    fi

    phone_seen_ts="$(
      sqlite3 "$log_db" \
        "SELECT ts
         FROM logs
         WHERE ts >= $since_ts
           AND ts BETWEEN $((input_seen_ts - 600)) AND $input_seen_ts
           AND feedback_log_body LIKE 'app_server.request%'
           AND feedback_log_body LIKE '%app_server.client_name=\"codex_chatgpt_ios_remote\"%'
           AND (
             feedback_log_body LIKE '%thread_id=$thread_id%'
             OR feedback_log_body LIKE '%thread.id=$thread_id%'
           )
         ORDER BY ts DESC
         LIMIT 1;"
    )"
    if [ -z "$phone_seen_ts" ]; then
      continue
    fi

    response_seen_ts="$(
      sqlite3 "$log_db" \
        "SELECT ts
         FROM logs
         WHERE ts >= $since_ts
           AND ts BETWEEN $input_seen_ts AND $((input_seen_ts + 300))
           AND feedback_log_body LIKE 'session_loop{thread_id=$thread_id}:%'
           AND feedback_log_body LIKE '%POST to https://gaccode.com/codex/v1/responses%'
           AND feedback_log_body LIKE '%model=$expected_model%'
           AND feedback_log_body LIKE '%codex.turn.reasoning_effort=xhigh%'
           AND (
             feedback_log_body LIKE '%thread_id=$thread_id%'
             OR feedback_log_body LIKE '%thread.id=$thread_id%'
           )
         ORDER BY ts DESC
         LIMIT 1;"
    )"

    if [ -n "$response_seen_ts" ]; then
      if [ -z "$best_response_ts" ] || [ "$response_seen_ts" -gt "$best_response_ts" ]; then
        best_thread="$thread_id"
        best_phone_ts="$phone_seen_ts"
        best_input_ts="$input_seen_ts"
        best_response_ts="$response_seen_ts"
      fi
    fi
  done

  if [ -n "$best_thread" ]; then
    log "Phone model path verified:"
    printf '  thread_id=%s\n' "$best_thread"
    printf '  phone_remote=%s\n' "$(sqlite3 "$log_db" "SELECT datetime($best_phone_ts,'unixepoch');")"
    printf '  user_input=%s\n' "$(sqlite3 "$log_db" "SELECT datetime($best_input_ts,'unixepoch');")"
    printf '  gaccode_response=%s\n' "$(sqlite3 "$log_db" "SELECT datetime($best_response_ts,'unixepoch');")"
    printf '  model=%s reasoning=xhigh\n' "$expected_model"
    return 0
  fi

  warn "Phone remote threads were found, but no complete user_input -> gaccode /responses chain was found."
  printf '%s\n' "$phone_threads" | sed 's/^/  thread_id=/'
  return 1
}

verify_plugin_local_state() {
  require_cmd rg

  local app_path="/Applications/Codex.app"
  local app_asar="$app_path/Contents/Resources/app.asar"
  local marker
  local enabled_count
  local patch_test="/Users/matrix/projects/dev/tools/codex-patch/test-patch-codex-plugins.mjs"
  local required_markers=(
    "codex-patch:auth-account-fields"
    "codex-patch:auth-account-output"
    "codex-patch:account-read-file-methods"
    "codex-patch:plugin-account-fallback"
    "codex-patch:prefer-local-chatgpt-account"
    "codex-patch:plugins-loading"
    "codex-patch:plugins-page-loading"
    "codex-patch:wham-desktop-auth"
    "codex-patch:desktop-feature-availability"
    "codex-patch:desktop-auth-token-fallback"
    "codex-patch:profile-visible-with-chatgpt"
    "codex-patch:profile-dropdown-visible"
    "codex-patch:usage-settings-visible"
    "codex-patch:local-usage-settings-visible"
    "codex-patch:local-desktop-settings-visible"
    "codex-patch:locked-use-settings-visible"
    "codex-patch:locked-use-data-fallback"
  )

  log "Checking Codex Desktop plugin local state."

  if [ ! -f "$app_asar" ]; then
    die "Missing Codex app.asar: $app_asar"
  fi

  for marker in "${required_markers[@]}"; do
    if ! rg -a -q "$marker" "$app_asar"; then
      die "Missing Codex plugin patch marker: $marker"
    fi
  done
  printf 'Plugin patch markers: %s present\n' "${#required_markers[@]}"

  if command -v codesign >/dev/null 2>&1; then
    codesign --verify --deep --strict "$app_path"
    printf 'Codex app codesign: ok\n'
  else
    warn "codesign command is unavailable; skipping app signature check."
  fi

  if [ -f "$patch_test" ]; then
    if command -v node >/dev/null 2>&1; then
      node --test "$patch_test" >/dev/null
      printf 'Codex plugin patch tests: ok\n'
    else
      warn "node command is unavailable; skipping plugin patch tests."
    fi
  fi

  enabled_count="$("$CODEX_BIN" plugin list | rg -c 'installed, enabled' || true)"
  enabled_count="${enabled_count:-0}"
  if [ "$enabled_count" -le 0 ]; then
    die "No installed, enabled plugins were found by '$CODEX_BIN plugin list'."
  fi
  printf 'Installed enabled plugins: %s\n' "$enabled_count"
}

verify_all() {
  require_macos
  require_cmd "$CODEX_BIN"

  status
  verify_phone_model_request
  verify_plugin_local_state

  log "Machine-verifiable checks passed."
  log "Final UI check still required: Codex Desktop plugin page should not show the ChatGPT sign-in gate."
}

switch_account() {
  require_macos
  require_cmd "$CODEX_BIN"

  set_gui_proxy
  stop_remote_daemon
  quit_desktop

  log "Logging out current Codex account."
  codex_env logout || true

  log "Starting Codex login. Complete the browser/device login with the new ChatGPT account."
  codex_env login

  open_desktop
  start_remote_daemon

  log "Switch flow finished. Run '$SCRIPT_NAME verify' after the phone refreshes the device list."
  status
}

status() {
  require_macos
  require_cmd "$CODEX_BIN"

  show_versions
  show_default_provider
  show_gui_proxy
  show_gui_api_key_status
  show_processes
  show_desktop_app_server_env_status
  show_login_status
  print_cloud_environments || true
}

verify() {
  require_macos
  require_cmd "$CODEX_BIN"

  show_gui_proxy
  show_gui_api_key_status
  show_processes
  show_desktop_app_server_env_status
  print_cloud_environments || true
  print_recent_phone_logs || true
}

verify_model() {
  require_cmd "$CODEX_BIN"
  require_cmd rg

  local cli_tmp="/tmp/codex-gaccode-cli-verify.$$"
  local desktop_tmp="/tmp/codex-gaccode-desktop-verify.$$"
  local env_file="$CODEX_HOME_DIR/gaccode.env"
  local gaccode_key
  local expected_model

  log "Checking system Codex CLI model call through default provider."
  if ! codex_env exec --json --skip-git-repo-check -C "$PWD" 'Reply exactly: OK' >"$cli_tmp" 2>&1 </dev/null; then
    sed -n '1,160p' "$cli_tmp" >&2
    die "System Codex CLI model check failed."
  fi

  if ! rg -q '"text":"OK"|\"text\": \"OK\"' "$cli_tmp" || ! rg -q '"type":"turn.completed"' "$cli_tmp"; then
    sed -n '1,160p' "$cli_tmp" >&2
    die "System Codex CLI did not return the expected OK turn."
  fi

  rg 'ERROR|thread.started|item.completed|turn.completed|OK' "$cli_tmp" | tail -n 20 || true

  if [ ! -x /Applications/Codex.app/Contents/Resources/codex ]; then
    warn "Desktop bundled Codex CLI not found; skipping Desktop app-server model check."
    return
  fi

  if [ ! -r "$env_file" ]; then
    die "Missing readable gaccode env file: $env_file"
  fi

  gaccode_key="$(sed -n -E 's/^(CODEX_API_KEY|GACCODE_API_KEY)=//p' "$env_file" | head -n 1)"
  if [ -z "$gaccode_key" ]; then
    die "No GACCODE_API_KEY value found in $env_file."
  fi

  expected_model="$(awk -F= '
    /^\[/ { in_table=1 }
    !in_table && $1 ~ /^[[:space:]]*model[[:space:]]*$/ {
      gsub(/[[:space:]\"]/, "", $2)
      print $2
      exit
    }
  ' "$CODEX_HOME_DIR/config.toml" 2>/dev/null || true)"
  expected_model="${expected_model:-gpt-5.5}"

  log "Checking Desktop app-server model call through gaccode."
  if [ "$USE_PROXY" -eq 1 ]; then
    env -u OPENAI_API_KEY -u CODEX_API_KEY \
      GACCODE_API_KEY="$gaccode_key" \
      HTTP_PROXY="$HTTP_PROXY_VALUE" \
      HTTPS_PROXY="$HTTPS_PROXY_VALUE" \
      ALL_PROXY="$ALL_PROXY_VALUE" \
      /Applications/Codex.app/Contents/Resources/codex debug app-server send-message-v2 'Reply exactly: OK' >"$desktop_tmp" 2>&1
  else
    env -u OPENAI_API_KEY -u CODEX_API_KEY \
      GACCODE_API_KEY="$gaccode_key" \
      /Applications/Codex.app/Contents/Resources/codex debug app-server send-message-v2 'Reply exactly: OK' >"$desktop_tmp" 2>&1
  fi

  if ! rg -q 'modelProvider.*gaccode|model_provider: "gaccode"' "$desktop_tmp" ||
     ! (grep -Fq "\"model\": \"$expected_model\"" "$desktop_tmp" || grep -Fq "model: \"$expected_model\"" "$desktop_tmp") ||
     ! rg -q '"text": "OK"|AgentMessage.*OK' "$desktop_tmp" ||
     ! rg -q 'thread/tokenUsage/updated|turn/completed' "$desktop_tmp"; then
    rg 'modelProvider|model_provider|model|OK|tokenUsage|turn/completed|Payment Required|402|Unauthorized|ERROR' "$desktop_tmp" >&2 || sed -n '1,220p' "$desktop_tmp" >&2
    die "Desktop app-server did not prove gaccode model usage."
  fi

  rg 'modelProvider|model_provider|\"model\"|\"text\": \"OK\"|AgentMessage.*OK|thread/tokenUsage/updated|turn/completed' "$desktop_tmp" | tail -n 40 || true
  log "Model checks passed."
}

fix_desktop() {
  require_macos
  require_cmd "$CODEX_BIN"

  unset_gui_api_key
  set_gui_gaccode_key
  set_gui_proxy
  quit_desktop
  open_desktop
  status
}

main() {
  local command="${1:-help}"
  if [ "$#" -gt 0 ]; then
    shift
  fi

  case "$command" in
    sync-remotes|sync-auth)
      "$SCRIPT_DIR/codex-sync-auth-to-remotes.sh" "$@"
      return
      ;;
  esac

  parse_options "$@"

  case "$command" in
    switch)
      switch_account
      ;;
    status)
      status
      ;;
    verify)
      verify
      ;;
    verify-model)
      verify_model
      ;;
    verify-phone-model)
      verify_phone_model_request
      ;;
    verify-all)
      verify_all
      ;;
    watch-phone)
      watch_phone_model_request
      ;;
    fix-desktop)
      fix_desktop
      ;;
    set-proxy)
      set_gui_proxy
      show_gui_proxy
      ;;
    unset-proxy)
      unset_gui_proxy
      show_gui_proxy
      ;;
    set-gaccode-key)
      set_gui_gaccode_key
      show_gui_api_key_status
      ;;
    unset-gaccode-key)
      unset_gui_gaccode_key
      show_gui_api_key_status
      ;;
    update-gaccode-key)
      update_gaccode_key
      show_gui_api_key_status
      ;;
    set-api-key)
      set_gui_api_key
      show_gui_api_key_status
      ;;
    unset-api-key)
      unset_gui_api_key
      show_gui_api_key_status
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      usage
      die "Unknown command: $command"
      ;;
  esac
}

main "$@"
