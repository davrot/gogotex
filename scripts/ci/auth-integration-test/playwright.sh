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
# Verbosity & reporter: set PLAYWRIGHT_VERBOSE=true to enable verbose Playwright output
PLAYWRIGHT_VERBOSE=${PLAYWRIGHT_VERBOSE:-false}
PLAYWRIGHT_REPORTER=${PLAYWRIGHT_REPORTER:-list}
# Per-test timeout (ms)
PLAYWRIGHT_PER_TEST_TIMEOUT=${PLAYWRIGHT_PER_TEST_TIMEOUT:-30000}

# Diagnostic summary (stderr only)
echo "Playwright: base_url=$PLAYWRIGHT_BASE_URL kc=$PLAYWRIGHT_KEYCLOAK redirect=$PLAYWRIGHT_REDIRECT_URI user=$TEST_USER reporter=$PLAYWRIGHT_REPORTER per_test_timeout=${PLAYWRIGHT_PER_TEST_TIMEOUT}ms" >&2

# Build the inner command; keep output visible when verbosity is requested
if [ "$PLAYWRIGHT_VERBOSE" = "true" ]; then
  INNER_CMD="npm install --no-audit --no-fund || true; npx playwright install --with-deps || true; npx playwright test tests/auth.spec.ts --timeout=$PLAYWRIGHT_PER_TEST_TIMEOUT --reporter=$PLAYWRIGHT_REPORTER"
else
  INNER_CMD="npm install --no-audit --no-fund >/dev/null 2>&1 || true; npx playwright install --with-deps >/dev/null 2>&1 || true; npx playwright test tests/auth.spec.ts --timeout=$PLAYWRIGHT_PER_TEST_TIMEOUT --reporter=$PLAYWRIGHT_REPORTER"
fi

# Run Playwright in the official Docker image on the same Docker network
# Artifacts (screenshots/traces) are written to frontend/test-results by Playwright.
docker run --rm --network "$NET" \
  -e PLAYWRIGHT_BASE_URL="$PLAYWRIGHT_BASE_URL" \
  -e PLAYWRIGHT_KEYCLOAK="$PLAYWRIGHT_KEYCLOAK" \
  -e PLAYWRIGHT_REDIRECT_URI="$PLAYWRIGHT_REDIRECT_URI" \
  -e TEST_USER="$TEST_USER" \
  -e TEST_PASS="$TEST_PASS" \
  -v "$ROOT_DIR/frontend":/app -w /app mcr.microsoft.com/playwright:latest \
  sh -c "$INNER_CMD"

