#!/usr/bin/env bash
# One-click Codex Desktop plugin patch entrypoint.
# Re-run this after Codex.app updates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/codex-patch/fix-codex-plugins.sh" "$@"
