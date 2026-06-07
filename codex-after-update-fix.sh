#!/usr/bin/env bash
# Update Codex.app to the latest Sparkle appcast release, then restore local
# plugin patches and verify the Chrome extension-backed browser connection.

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="${CODEX_APP:-/Applications/Codex.app}"
FIX_SCRIPT="$TOOLS_DIR/fix-codex-plugins.sh"
DIAG_SCRIPT="$HOME/.codex/skills/codex-chrome-plugin-recovery/scripts/diagnose-codex-chrome-plugin.sh"
APPCAST_URL="${CODEX_APPCAST_URL:-https://persistent.oaistatic.com/codex-app-prod/appcast.xml}"

DO_UPDATE=1
DO_PATCH=1
DO_DIAGNOSE=1
DO_LAUNCH=1
FORCE_UPDATE=0
KILL_STALE_CHROME_KERNELS=0
AD_HOC_SIGN=0
LAST_BACKUP_APP=""
LAST_INSTALLED_APP=0

log() { printf '[codex-update-fix] %s\n' "$*"; }
warn() { printf '[codex-update-fix][warn] %s\n' "$*" >&2; }
die() { printf '[codex-update-fix][error] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  codex-after-update-fix.sh [options]

Options:
  --skip-update                Do not download/install a newer Codex.app.
  --force-update               Reinstall latest appcast build even if already current.
  --update-only                Only update Codex.app; do not patch, diagnose, or launch.
  --diagnose-only              Only run Chrome/Codex plugin diagnostics.
  --skip-patch                 Do not run the Codex app/plugin patch.
  --skip-diagnose              Do not run diagnostics after patching.
  --no-launch                  Do not launch Codex.app at the end.
  --launch                     Launch Codex.app at the end (default).
  --kill-stale-chrome-kernels  Terminate only stale Chrome-plugin kernel.js processes.
  --ad-hoc-sign                Force ad-hoc signing instead of the stable local signing identity.
  -h, --help                   Show this help.

Notes:
  By default this downloads the latest full arm64 zip from the official Codex
  Sparkle appcast, installs it, then reapplies local plugin patches.
EOF
}

while (($#)); do
  case "$1" in
    --skip-update)
      DO_UPDATE=0
      ;;
    --force-update)
      FORCE_UPDATE=1
      ;;
    --update-only)
      DO_UPDATE=1
      DO_PATCH=0
      DO_DIAGNOSE=0
      DO_LAUNCH=0
      ;;
    --diagnose-only)
      DO_UPDATE=0
      DO_PATCH=0
      DO_DIAGNOSE=1
      DO_LAUNCH=0
      ;;
    --skip-patch)
      DO_PATCH=0
      ;;
    --skip-diagnose)
      DO_DIAGNOSE=0
      ;;
    --no-launch)
      DO_LAUNCH=0
      ;;
    --launch)
      DO_LAUNCH=1
      ;;
    --kill-stale-chrome-kernels)
      KILL_STALE_CHROME_KERNELS=1
      ;;
    --ad-hoc-sign)
      AD_HOC_SIGN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
  shift
done

app_version() {
  if [[ -d "$APP" ]]; then
    defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true
  fi
}

preflight() {
  [[ -d "$APP" ]] || die "Codex.app not found at $APP"
  [[ -x "$FIX_SCRIPT" ]] || die "Patch wrapper not executable: $FIX_SCRIPT"
  command -v curl >/dev/null 2>&1 || die "curl not found"
  command -v node >/dev/null 2>&1 || die "node not found"
  command -v python3 >/dev/null 2>&1 || die "python3 not found"
  command -v ditto >/dev/null 2>&1 || die "ditto not found"
  if ((DO_PATCH)); then
    command -v npx >/dev/null 2>&1 || die "npx not found"
  fi
  if ((DO_DIAGNOSE)); then
    [[ -x "$DIAG_SCRIPT" ]] || die "Diagnostic script not executable: $DIAG_SCRIPT"
  fi
}

app_build() {
  if [[ -d "$APP" ]]; then
    defaults read "$APP/Contents/Info" CFBundleVersion 2>/dev/null || true
  fi
}

codex_app_process_pids() {
  ps -axo pid=,command= | awk -v app="$APP/Contents/" 'index($0, app) { print $1 }'
}

kill_codex_app_processes() {
  local pids

  pids="$(codex_app_process_pids || true)"
  [[ -n "$pids" ]] || return 0

  log "Terminating Codex.app helper processes..."
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill -TERM "$pid" 2>/dev/null || true
  done <<< "$pids"

  for _ in {1..20}; do
    [[ -n "$(codex_app_process_pids || true)" ]] || return 0
    sleep 0.25
  done

  pids="$(codex_app_process_pids || true)"
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill -KILL "$pid" 2>/dev/null || true
  done <<< "$pids"
}

quit_codex() {
  if pgrep -x Codex >/dev/null 2>&1; then
    log "Quitting Codex..."
    osascript -e 'quit app "Codex"' >/dev/null 2>&1 || true
    for _ in {1..40}; do
      pgrep -x Codex >/dev/null 2>&1 || return 0
      sleep 0.25
    done
    pkill -TERM -x Codex 2>/dev/null || true
    for _ in {1..20}; do
      pgrep -x Codex >/dev/null 2>&1 || return 0
      sleep 0.25
    done
    pkill -KILL -x Codex 2>/dev/null || true
  fi

  kill_codex_app_processes
}

launch_codex() {
  open "$APP" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    pgrep -f "$APP/Contents/MacOS/Codex" >/dev/null 2>&1 && return 0
    sleep 1
  done

  warn "LaunchServices did not start Codex.app; launching app binary directly."
  nohup "$APP/Contents/MacOS/Codex" >/tmp/codex-desktop-launch.log 2>&1 &
}

latest_appcast_info() {
  local appcast="$1"
  python3 - "$appcast" <<'PY'
import sys
import xml.etree.ElementTree as ET

ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
root = ET.parse(sys.argv[1]).getroot()

for item in root.findall("./channel/item"):
    hardware = (item.findtext("sparkle:hardwareRequirements", namespaces=ns) or "").strip()
    if hardware and hardware != "arm64":
        continue
    build = (item.findtext("sparkle:version", namespaces=ns) or "").strip()
    version = (item.findtext("sparkle:shortVersionString", namespaces=ns) or item.findtext("title") or "").strip()
    enclosure = item.find("enclosure")
    if not build or not version or enclosure is None:
        continue
    url = enclosure.attrib.get("url", "").strip()
    length = enclosure.attrib.get("length", "").strip()
    if url:
        print("\t".join([version, build, url, length]))
        raise SystemExit(0)

raise SystemExit("No arm64 Codex app update found in appcast")
PY
}

disable_visible_backup_apps() {
  local backup_root="$HOME/.codex/backups/codex-app"
  local old target

  [[ -d "$backup_root" ]] || return 0

  while IFS= read -r old; do
    [[ -n "$old" ]] || continue
    target="$old.disabled"
    if [[ -e "$target" ]]; then
      target="$old.disabled-$(date +%Y%m%d%H%M%S)"
    fi
    log "Renaming visible Codex.app backup: $old -> $target"
    mv "$old" "$target"
  done < <(find "$backup_root" -maxdepth 1 -type d -name 'Codex-*.app' -print)
}

install_latest_codex() {
  local work appcast info latest_version latest_build latest_url latest_length current_version current_build
  work="$(mktemp -d /tmp/codex_app_update_XXXXXX)"
  trap 'rm -rf "${work:-}"; trap - RETURN' RETURN

  log "Checking appcast: $APPCAST_URL"
  appcast="$work/appcast.xml"
  curl -fsSL "$APPCAST_URL" -o "$appcast"

  info="$(latest_appcast_info "$appcast")"
  IFS=$'\t' read -r latest_version latest_build latest_url latest_length <<< "$info"
  current_version="$(app_version)"
  current_build="$(app_build)"

  log "Latest Codex.app: ${latest_version} (build ${latest_build})"
  log "Current Codex.app: ${current_version:-unknown} (build ${current_build:-unknown})"

  if (( ! FORCE_UPDATE )) && [[ "$current_build" =~ ^[0-9]+$ ]] && [[ "$latest_build" =~ ^[0-9]+$ ]] && (( current_build >= latest_build )); then
    log "Codex.app is already current; skipping download."
    return 0
  fi

  local zip_path unpack_dir new_app new_version new_build backup_root backup_app
  zip_path="$work/$(basename "$latest_url")"
  unpack_dir="$work/unpacked"
  mkdir -p "$unpack_dir"

  if [[ -n "$latest_length" ]]; then
    log "Downloading ${latest_version} (${latest_length} bytes)..."
  else
    log "Downloading ${latest_version}..."
  fi
  curl -fL --progress-bar -o "$zip_path" "$latest_url"

  log "Unpacking update..."
  ditto -x -k "$zip_path" "$unpack_dir"
  new_app="$(find "$unpack_dir" -maxdepth 3 -type d -name 'Codex.app' -print -quit)"
  [[ -n "$new_app" && -d "$new_app" ]] || die "Downloaded update did not contain Codex.app"

  new_version="$(defaults read "$new_app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
  new_build="$(defaults read "$new_app/Contents/Info" CFBundleVersion 2>/dev/null || true)"
  [[ "$new_build" == "$latest_build" ]] || die "Downloaded Codex.app build mismatch: expected $latest_build, got ${new_build:-unknown}"

  log "Verifying downloaded app signature..."
  codesign --verify --deep --strict "$new_app" >/dev/null 2>&1 || die "Downloaded Codex.app signature verification failed"

  quit_codex

  backup_root="$HOME/.codex/backups/codex-app"
  mkdir -p "$backup_root"
  backup_app="$backup_root/Codex-${current_version:-unknown}-${current_build:-unknown}-$(date +%Y%m%d%H%M%S).app.disabled"

  log "Backing up current app to: $backup_app"
  rm -rf "$backup_app"
  mv "$APP" "$backup_app"
  LAST_BACKUP_APP="$backup_app"

  log "Installing Codex.app ${new_version:-$latest_version}..."
  if ! ditto "$new_app" "$APP"; then
    warn "Install failed; restoring backup."
    rm -rf "$APP"
    mv "$backup_app" "$APP"
    die "Codex.app install failed"
  fi

  LAST_INSTALLED_APP=1
  log "Installed Codex.app ${new_version:-$latest_version} (build ${new_build:-$latest_build})."
}

restore_last_backup() {
  [[ "$LAST_INSTALLED_APP" -eq 1 ]] || return 1
  [[ -n "$LAST_BACKUP_APP" && -d "$LAST_BACKUP_APP" ]] || return 1

  warn "Restoring previous Codex.app because post-update patching failed: $LAST_BACKUP_APP"
  quit_codex || true
  rm -rf "$APP"
  ditto "$LAST_BACKUP_APP" "$APP"
}

show_stale_chrome_kernels() {
  ps -axo pid,ppid,command | awk '
    /\/Applications\/Codex\.app\/Contents\/Resources\/node --experimental-vm-modules .*kernel\.js/ &&
    /chrome-plugin-chrome-openai-bundled/ {
      print
    }
  '
}

kill_stale_chrome_kernels() {
  local pids
  pids="$(show_stale_chrome_kernels | awk '{print $1}')"
  if [[ -z "$pids" ]]; then
    log "No stale Chrome-plugin kernel.js processes found."
    return 0
  fi

  log "Terminating stale Chrome-plugin kernel.js processes:"
  show_stale_chrome_kernels
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill -TERM "$pid" 2>/dev/null || true
  done <<< "$pids"
}

main() {
  preflight

  local version
  version="$(app_version)"
  log "Codex.app: $APP${version:+ (version $version)}"
  disable_visible_backup_apps

  if ((DO_UPDATE)); then
    install_latest_codex
  else
    log "Skipping update step."
  fi

  if ((DO_PATCH)); then
    log "Running Codex plugin patch..."
    local patch_code=0
    if ((AD_HOC_SIGN)); then
      CODEX_PATCH_SIGN_IDENTITY="-" "$FIX_SCRIPT" || patch_code=$?
    else
      "$FIX_SCRIPT" || patch_code=$?
    fi
    if [[ "$patch_code" -ne 0 ]]; then
      warn "Codex plugin patch failed with exit $patch_code."
      if restore_last_backup; then
        warn "Restored previous Codex.app after patch failure."
      else
        warn "No post-update backup was available to restore."
      fi
      exit "$patch_code"
    fi
  else
    log "Skipping patch step."
  fi

  if ((KILL_STALE_CHROME_KERNELS)); then
    kill_stale_chrome_kernels
  else
    local stale
    stale="$(show_stale_chrome_kernels || true)"
    if [[ -n "$stale" ]]; then
      warn "Stale Chrome-plugin kernels still exist. Re-run with --kill-stale-chrome-kernels if that old session keeps failing."
      printf '%s\n' "$stale"
    fi
  fi

  if ((DO_DIAGNOSE)); then
    log "Running Chrome plugin diagnostics..."
    "$DIAG_SCRIPT"
  else
    log "Skipping diagnostics."
  fi

  if ((DO_LAUNCH)); then
    log "Launching Codex.app..."
    launch_codex
  else
    log "Not launching Codex.app."
  fi

  log "Done."
}

main
