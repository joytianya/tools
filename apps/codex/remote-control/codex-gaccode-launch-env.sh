#!/usr/bin/env bash
# Keep Codex Desktop's GUI launch environment aligned with ~/.codex/gaccode.env.

set -euo pipefail

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
ENV_FILE="$CODEX_HOME_DIR/gaccode.env"
HTTP_PROXY_VALUE="${CODEX_GUI_HTTP_PROXY:-http://127.0.0.1:7890}"
HTTPS_PROXY_VALUE="${CODEX_GUI_HTTPS_PROXY:-$HTTP_PROXY_VALUE}"
ALL_PROXY_VALUE="${CODEX_GUI_ALL_PROXY:-socks5h://127.0.0.1:7890}"

if [ ! -r "$ENV_FILE" ]; then
  exit 0
fi

gaccode_key="$(sed -n -E 's/^(GACCODE_API_KEY|CODEX_API_KEY)=//p' "$ENV_FILE" | head -n 1)"
if [ -z "$gaccode_key" ]; then
  exit 0
fi

launchctl setenv GACCODE_API_KEY "$gaccode_key"
launchctl setenv HTTP_PROXY "$HTTP_PROXY_VALUE"
launchctl setenv HTTPS_PROXY "$HTTPS_PROXY_VALUE"
launchctl setenv ALL_PROXY "$ALL_PROXY_VALUE"
