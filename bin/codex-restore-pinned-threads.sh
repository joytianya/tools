#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT_DIR/apps/codex/desktop-recovery/codex-restore-pinned-threads.sh" "$@"
