#!/usr/bin/env bash
# Restore pinned Codex Desktop threads that are present in local state but
# missing from the sidebar cache.

set -euo pipefail

STATE_FILE="${CODEX_STATE_FILE:-$HOME/.codex/.codex-global-state.json}"
CODEX_APP="${CODEX_APP:-/Applications/Codex.app}"

log() {
  printf '[codex-pins] %s\n' "$*"
}

die() {
  printf '[codex-pins][error] %s\n' "$*" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || die "This recovery script requires macOS."
[[ -r "$STATE_FILE" ]] || die "Codex state file is not readable: $STATE_FILE"
[[ -d "$CODEX_APP" ]] || die "Codex.app was not found: $CODEX_APP"
command -v jq >/dev/null 2>&1 || die "jq is required but was not found."

thread_ids="$({
  jq -r '
    .["pinned-thread-ids"] // []
    | if type == "array" then .[] else error("pinned-thread-ids is not an array") end
    | select(type == "string" and length > 0)
  ' "$STATE_FILE"
})" || die "Could not read pinned thread IDs from $STATE_FILE"

[[ -n "$thread_ids" ]] || die "No pinned thread IDs were found."

thread_count="$(printf '%s\n' "$thread_ids" | wc -l | tr -d ' ')"
log "Found $thread_count pinned threads."

if ! pgrep -x Codex >/dev/null 2>&1; then
  log "Starting Codex.app..."
  open "$CODEX_APP"
  sleep 3
fi

index=0
while IFS= read -r thread_id; do
  [[ -n "$thread_id" ]] || continue
  index=$((index + 1))
  log "Loading pinned thread $index/$thread_count..."
  open "codex://threads/$thread_id"
  sleep 1
done <<< "$thread_ids"

osascript -e 'tell application "Codex" to activate' >/dev/null 2>&1 || true
log "Finished. Codex should now show all $thread_count pinned threads."
