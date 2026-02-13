#!/usr/bin/env bash
set -euo pipefail

# Convenience helper: start the auth container with the inline go-document service enabled
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
DOC_SERVICE_INLINE=true docker compose -f gogotex-support-services/compose.yaml up -d gogotex-auth

echo "Started gogotex-auth with DOC_SERVICE_INLINE=true (in-process go-document service)."