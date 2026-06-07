#!/usr/bin/env bash
# Run the standalone Codex CLI with the gaccode key, even outside interactive zsh.

set -euo pipefail

default_real_codex="$HOME/.codex/packages/standalone/current/bin/codex.real"
if [ ! -x "$default_real_codex" ]; then
  default_real_codex="$HOME/.codex/packages/standalone/current/bin/codex"
fi

REAL_CODEX="${CODEX_REAL_BIN:-$default_real_codex}"
ENV_FILE="${CODEX_GACCODE_ENV:-$HOME/.codex/gaccode.env}"

if [ ! -x "$REAL_CODEX" ]; then
  printf 'codex wrapper: real Codex binary not executable: %s\n' "$REAL_CODEX" >&2
  exit 127
fi

if [ -r "$ENV_FILE" ] && [ -z "${GACCODE_API_KEY:-}" ]; then
  gaccode_key="$(sed -n -E 's/^(GACCODE_API_KEY|CODEX_API_KEY)=//p' "$ENV_FILE" | head -n 1)"
  if [ -n "$gaccode_key" ]; then
    export GACCODE_API_KEY="$gaccode_key"
  fi
fi

unset OPENAI_API_KEY
unset CODEX_API_KEY

exec "$REAL_CODEX" "$@"
