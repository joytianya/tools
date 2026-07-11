#!/usr/bin/env bash
# Safely remove stale macOS code signing clone directories for Codex.app.

set -u

BUNDLE_ID="${CODEX_CODE_SIGN_CLONE_BUNDLE_ID:-com.openai.codex}"
MIN_AGE_SECONDS="${CODEX_CODE_SIGN_CLONE_MIN_AGE_SECONDS:-3600}"
CLEAN_INTERVAL_SECONDS="${CODEX_CODE_SIGN_CLONE_CLEAN_INTERVAL_SECONDS:-3600}"
STATE_FILE="${CODEX_CODE_SIGN_CLONE_STATE_FILE:-$HOME/.codex/code-sign-clone-cleanup.last}"
DRY_RUN=0
FORCE=0
QUIET=0

log() {
  [ "$QUIET" -eq 1 ] && return 0
  printf '[code-sign-clone-cleanup] %s\n' "$*"
}

warn() {
  printf '[code-sign-clone-cleanup][warn] %s\n' "$*" >&2
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run] [--force] [--quiet]

Environment:
  CODEX_CODE_SIGN_CLONE_MIN_AGE_SECONDS      Minimum age before deletion. Default: 3600.
  CODEX_CODE_SIGN_CLONE_CLEAN_INTERVAL_SECONDS  Rate-limit interval. Default: 3600.
  CODEX_CODE_SIGN_CLONE_BUNDLE_ID            Bundle id prefix. Default: com.openai.codex.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --force)
      FORCE=1
      ;;
    --quiet)
      QUIET=1
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
  shift
done

case "$MIN_AGE_SECONDS" in
  ''|*[!0-9]*)
    warn "Invalid CODEX_CODE_SIGN_CLONE_MIN_AGE_SECONDS: $MIN_AGE_SECONDS"
    exit 2
    ;;
esac

case "$CLEAN_INTERVAL_SECONDS" in
  ''|*[!0-9]*)
    warn "Invalid CODEX_CODE_SIGN_CLONE_CLEAN_INTERVAL_SECONDS: $CLEAN_INTERVAL_SECONDS"
    exit 2
    ;;
esac

now="$(date +%s)"

if [ "$FORCE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ] && [ "$CLEAN_INTERVAL_SECONDS" -gt 0 ] && [ -r "$STATE_FILE" ]; then
  last_run="$(sed -n '1p' "$STATE_FILE" 2>/dev/null || true)"
  case "$last_run" in
    ''|*[!0-9]*)
      ;;
    *)
      if [ "$((now - last_run))" -lt "$CLEAN_INTERVAL_SECONDS" ]; then
        exit 0
      fi
      ;;
  esac
fi

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
  printf '%s\n' "$now" >"$STATE_FILE" 2>/dev/null || true
fi

parents="$(find /private/var/folders -type d -name "${BUNDLE_ID}.code_sign_clone" -print 2>/dev/null | sort)"
[ -n "$parents" ] || exit 0

removed=0
kept=0
skipped=0
removed_kb=0

while IFS= read -r parent; do
  [ -n "$parent" ] || continue
  [ -d "$parent" ] || continue

  held="$(
    lsof -F n +D "$parent" 2>/dev/null |
      sed -n 's/^n//p' |
      awk -v base="$parent" 'index($0, base "/") == 1 { sub("^" base "/", ""); split($0, a, "/"); print a[1] }' |
      sort -u
  )"

  for dir in "$parent"/code_sign_clone.*; do
    [ -d "$dir" ] || continue
    name="${dir##*/}"

    if printf '%s\n' "$held" | grep -Fxq "$name"; then
      kept=$((kept + 1))
      continue
    fi

    mtime="$(stat -f '%m' "$dir" 2>/dev/null || printf '%s' "$now")"
    age="$((now - mtime))"
    if [ "$age" -lt "$MIN_AGE_SECONDS" ]; then
      skipped=$((skipped + 1))
      continue
    fi

    size_kb="$(du -sk "$dir" 2>/dev/null | awk '{ print $1 }')"
    case "$size_kb" in
      ''|*[!0-9]*)
        size_kb=0
        ;;
    esac

    if [ "$DRY_RUN" -eq 1 ]; then
      log "Would remove $dir (${size_kb}K, age ${age}s)"
      removed=$((removed + 1))
      removed_kb=$((removed_kb + size_kb))
      continue
    fi

    rm -rf -- "$dir" 2>/dev/null || {
      warn "Failed to remove $dir"
      continue
    }
    log "Removed $dir (${size_kb}K, age ${age}s)"
    removed=$((removed + 1))
    removed_kb=$((removed_kb + size_kb))
  done
done <<EOF
$parents
EOF

if [ "$removed" -gt 0 ] || [ "$DRY_RUN" -eq 1 ]; then
  log "Summary: removed=$removed kept_in_use=$kept skipped_young=$skipped logical_kb=$removed_kb"
fi
