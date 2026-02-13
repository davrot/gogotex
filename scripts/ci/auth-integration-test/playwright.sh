#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
NET=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' keycloak-keycloak || true)
if [ -z "$NET" ]; then
  echo "ERROR: cannot determine Docker network for Keycloak" >&2
  exit 2
fi

# environment defaults (can be overridden by caller)
PLAYWRIGHT_BASE_URL=${PLAYWRIGHT_BASE_URL:-http://frontend}
PLAYWRIGHT_KEYCLOAK=${PLAYWRIGHT_KEYCLOAK:-http://keycloak-keycloak:8080/sso}
PLAYWRIGHT_REDIRECT_URI=${PLAYWRIGHT_REDIRECT_URI:-http://frontend/auth/callback}
TEST_USER=${TEST_USER:-testuser}
TEST_PASS=${TEST_PASS:-$(cat "$ROOT_DIR/gogotex-support-services/keycloak-service/testuser_password.txt" 2>/dev/null || echo "Test123!")}

echo "Playwright: base_url=$PLAYWRIGHT_BASE_URL kc=$PLAYWRIGHT_KEYCLOAK redirect=$PLAYWRIGHT_REDIRECT_URI user=$TEST_USER"

docker run --rm --network "$NET" \
  -e PLAYWRIGHT_BASE_URL="$PLAYWRIGHT_BASE_URL" \
  -e PLAYWRIGHT_KEYCLOAK="$PLAYWRIGHT_KEYCLOAK" \
  -e PLAYWRIGHT_REDIRECT_URI="$PLAYWRIGHT_REDIRECT_URI" \
  -e TEST_USER="$TEST_USER" \
  -e TEST_PASS="$TEST_PASS" \
  -v "$ROOT_DIR/frontend":/app -w /app mcr.microsoft.com/playwright:latest \
  sh -c "npm install --no-audit --no-fund >/dev/null 2>&1 || true; npx playwright install --with-deps >/dev/null 2>&1 || true; npx playwright test tests/auth.spec.ts --timeout=30000"
