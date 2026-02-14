#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
# validate expected frontend path early to fail fast with a clear message
if [ ! -f "$ROOT_DIR/frontend/package.json" ]; then
  echo "ERROR: cannot find frontend package.json at $ROOT_DIR/frontend/package.json" >&2
  echo "(playwright.sh computed ROOT_DIR=$ROOT_DIR — check script location or invocation)" >&2
  exit 2
fi
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
PLAYWRIGHT_PER_TEST_TIMEOUT=${PLAYWRIGHT_PER_TEST_TIMEOUT:-120000}
# Enable Playwright trace: off|on|on-first-retry
PLAYWRIGHT_TRACE=${PLAYWRIGHT_TRACE:-off}

# Diagnostic summary (stderr only)
echo "Playwright: base_url=$PLAYWRIGHT_BASE_URL kc=$PLAYWRIGHT_KEYCLOAK redirect=$PLAYWRIGHT_REDIRECT_URI user=$TEST_USER reporter=$PLAYWRIGHT_REPORTER per_test_timeout=${PLAYWRIGHT_PER_TEST_TIMEOUT}ms trace=$PLAYWRIGHT_TRACE" >&2

# Build the inner command; keep output visible when verbosity is requested
if [ "$PLAYWRIGHT_VERBOSE" = "true" ]; then
  INNER_CMD="npm install --no-audit --no-fund || true; npx playwright install --with-deps || true; npx playwright test tests/auth.spec.ts --timeout=$PLAYWRIGHT_PER_TEST_TIMEOUT --reporter=$PLAYWRIGHT_REPORTER && npx playwright test tests/realtime.spec.ts --timeout=120000 --reporter=$PLAYWRIGHT_REPORTER && npx playwright test tests/persistence-yjs.spec.ts --timeout=120000 --reporter=$PLAYWRIGHT_REPORTER"
else
  INNER_CMD="npm install --no-audit --no-fund >/dev/null 2>&1 || true; npx playwright install --with-deps >/dev/null 2>&1 || true; npx playwright test tests/auth.spec.ts --timeout=$PLAYWRIGHT_PER_TEST_TIMEOUT --reporter=$PLAYWRIGHT_REPORTER && npx playwright test tests/realtime.spec.ts --timeout=$PLAYWRIGHT_PER_TEST_TIMEOUT --reporter=$PLAYWRIGHT_REPORTER"
fi
# append optional trace flag
if [ "$PLAYWRIGHT_TRACE" != "off" ]; then
  INNER_CMD="$INNER_CMD --trace $PLAYWRIGHT_TRACE"
fi

# Prefer a local cached image to avoid re-installing browsers & npm deps every run.
# If not present we fall back to the official Playwright image.
PLAYWRIGHT_LOCAL_IMAGE=${PLAYWRIGHT_LOCAL_IMAGE:-gogotex/playwright:ci}
PLAYWRIGHT_FORCE_OFFICIAL=${PLAYWRIGHT_FORCE_OFFICIAL:-false}
DOCKER_IMAGE="mcr.microsoft.com/playwright:latest"
PREPARE_NODE_CMD=""
DOCKER_RUN_ENTRYPOINT=""
if [ "$PLAYWRIGHT_FORCE_OFFICIAL" != "true" ] && docker image inspect "$PLAYWRIGHT_LOCAL_IMAGE" >/dev/null 2>&1; then
  DOCKER_IMAGE="$PLAYWRIGHT_LOCAL_IMAGE"
  # copy pre-baked node_modules into the mounted /app if the host doesn't provide node_modules
  PREPARE_NODE_CMD="cp -a /prebaked_node_modules /app/node_modules 2>/dev/null || true;"
  # The prebaked image uses an Entrypoint that expects exec "$@" — ensure we run via /bin/sh -c
  DOCKER_RUN_ENTRYPOINT="--entrypoint /bin/sh"
fi

# Wait for Keycloak OIDC readiness (avoid transient DB/startup flakes)
KC_WAIT_TIMEOUT=${KC_WAIT_TIMEOUT:-60}
KC_POLL_INTERVAL=${KC_POLL_INTERVAL:-2}
KC_BASE_URL=${PLAYWRIGHT_KEYCLOAK%/sso} # strip trailing /sso if present
KC_REALM_ENDPOINT="${KC_BASE_URL}/sso/realms/gogotex/protocol/openid-connect/certs"

echo "Waiting up to ${KC_WAIT_TIMEOUT}s for Keycloak OIDC endpoint..." >&2
kc_ok=0
tries=$((KC_WAIT_TIMEOUT / KC_POLL_INTERVAL))
for i in $(seq 1 $tries); do
  code=$(docker run --rm --network "$NET" curlimages/curl -sS --max-time 5 -o /dev/null -w "%{http_code}" "$KC_REALM_ENDPOINT" 2>/dev/null || echo 000)
  if [ "$code" = "200" ]; then
    kc_ok=1
    break
  fi
  sleep $KC_POLL_INTERVAL
done
if [ "$kc_ok" -ne 1 ]; then
  echo "ERROR: Keycloak OIDC endpoint not available after ${KC_WAIT_TIMEOUT}s (last_code=${code})." >&2
  echo "Check 'docker ps -a' and 'docker logs keycloak-keycloak' for details." >&2
  exit 1
fi

# Run Playwright in the selected Docker image on the same Docker network
# Artifacts (screenshots/traces) are written to frontend/test-results by Playwright.
docker run --rm $DOCKER_RUN_ENTRYPOINT --network "$NET" \
  -e PLAYWRIGHT_BASE_URL="$PLAYWRIGHT_BASE_URL" \
  -e PLAYWRIGHT_KEYCLOAK="$PLAYWRIGHT_KEYCLOAK" \
  -e PLAYWRIGHT_REDIRECT_URI="$PLAYWRIGHT_REDIRECT_URI" \
  -e TEST_USER="$TEST_USER" \
  -e TEST_PASS="$TEST_PASS" \
  -v "$ROOT_DIR/frontend":/app -w /app "$DOCKER_IMAGE" \
  -c "$PREPARE_NODE_CMD $INNER_CMD"

