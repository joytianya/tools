#!/usr/bin/env bash
# Temporary compatibility entrypoint. Prefer ./bin/fix-codex-plugins.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/bin/fix-codex-plugins.sh" "$@"
