#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec node "$ROOT_DIR/integrations/paseo/edge-tts/paseo-edge-tts-bridge.mjs" "$@"
