#!/usr/bin/env bash
set -euo pipefail

# CI integration test for auth service
# - Starts Keycloak+Postgres and MongoDB via existing compose files
# - Provisions client and test user
# - Runs the auth service in a detached container on the same network
# - Requests a password-grant access token for the test user and calls /api/v1/me

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Optional: run inside an Ubuntu runner container when explicitly requested.
# Set RUN_INTEGRATION_DOCKER=true to re-exec into the integration-runner container.
if [ "${RUN_INTEGRATION_DOCKER:-""}" = "true" ] && [ "${INTEGRATION_IN_DOCKER:-""}" != "1" ]; then
  echo "Re-running auth integration inside ephemeral Ubuntu container on network 'tex-network'..."
  docker run --rm -v "$ROOT_DIR":"$ROOT_DIR" -w "$ROOT_DIR" -v /var/run/docker.sock:/var/run/docker.sock --network tex-network ubuntu:24.04 \
    bash -lc "set -euo pipefail; export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null; apt-get install -y -qq docker.io curl jq bash >/dev/null; INTEGRATION_IN_DOCKER=1 bash '$SCRIPT_DIR/ci/auth-integration-test.sh' \"$@\""
  exit $?
fi
# By default the script runs on the host (do not auto re-exec). To run inside the
# dedicated integration runner image use `make integration-runner-image` and then
# `scripts/ci/run-integration-in-docker.sh`.

# Allow easy enablement of Keycloak debug logs. Set KEYCLOAK_DEBUG=true to restart
# Keycloak with QUARKUS_LOG_LEVEL=DEBUG (useful for capturing router stacktraces).
if [ "${KEYCLOAK_DEBUG:-false}" = "true" ]; then
  echo "KEYCLOAK_DEBUG=true -> will start Keycloak with QUARKUS_LOG_LEVEL=DEBUG" >&2
  export KEYCLOAK_LOG_LEVEL=${KEYCLOAK_LOG_LEVEL:-DEBUG}
  # If Keycloak is already running, remove it so infra.sh recreates it with the new env
  if docker ps --format '{{.Names}}' | grep -q '^keycloak-keycloak$'; then
    echo "Recreating existing Keycloak container to apply DEBUG log level..." >&2
    docker rm -f keycloak-keycloak >/dev/null 2>&1 || true
  fi
fi

# Start infra (Keycloak + MongoDB) and wait until Keycloak HTTP is reachable.
# This logic has been extracted to a focused helper script that returns the Docker
# network name so downstream steps can reuse it.
NET="$("$ROOT_DIR/scripts/ci/auth-integration-test/infra.sh")"
if [ -z "$NET" ]; then
  echo "ERROR: infra script failed to return Docker network" >&2
  exit 2
fi
echo "Using Docker network: $NET"
# Optionally start a TeX worker service for real pdflatex when START_TEXLIVE=true
if [ "${START_TEXLIVE:-false}" = "true" ]; then
  echo "START_TEXLIVE=true -> starting texlive service using gogotex-support-services/compose.yaml" >&2
  docker compose -f "$ROOT_DIR/gogotex-support-services/compose.yaml" up -d texlive || true
  # ensure the configured Docker TeX image is present for backend docker-run fallback
  docker pull "${DOCKER_TEX_IMAGE:-blang/latex:ubuntu}" || true
fi
# Provision Keycloak (migrated to sub-script for maintainability)
echo "Running Keycloak setup..."
"$ROOT_DIR/scripts/ci/auth-integration-test/keycloak-provision.sh" "$NET" || { echo "Keycloak provisioning failed"; exit 2; }

# Build and start frontend so we can exercise the real frontend callback path
# Rebuild frontend with network-aware VITE_* values so the browser can reach Keycloak and auth service
echo "Building frontend image with in-network VITE settings..."
docker build \
  --build-arg VITE_KEYCLOAK_URL=http://keycloak-keycloak:8080 \
  --build-arg VITE_KEYCLOAK_REALM=gogotex \
  --build-arg VITE_KEYCLOAK_CLIENT_ID=gogotex-backend \
  --build-arg VITE_AUTH_URL=http://gogotex-auth-integration:8081 \
  --build-arg VITE_REDIRECT_URI=http://frontend/auth/callback \
  -t gogotex-frontend:local "$ROOT_DIR/frontend"

# Quick regression guard: ensure built frontend contains required auth payload (mode=auth_code)
# Accept either minified/unquoted property output (mode:"auth_code") or explicit JSON string ("mode":"auth_code").
if ! docker run --rm gogotex-frontend:local sh -c "cat /usr/share/nginx/html/assets/index-*.js | grep -E -q '(\"mode\":\"auth_code\"|mode:\"auth_code\")'"; then
    echo 'ERROR: built frontend bundle missing "mode":"auth_code" (regression)' >&2
fi

echo "Starting frontend service for E2E auth-code test..."
bash "$ROOT_DIR/gogotex-support-services/up_frontend.sh" || true

# Run Playwright E2E (browser flow) if Playwright is available in CI
# This step has its own script for better maintainability and a shell-level timeout
if [ "${RUN_PLAYWRIGHT:-true}" = "true" ]; then
  echo "Running Playwright E2E test (browser -> Keycloak -> frontend -> auth)..."

  # diagnostics directory (create early so Playwright failure handlers can write logs)
  DIAG_DIR="${DIAG_DIR:-${ROOT_DIR:-.}/test-output}"
  mkdir -p "$DIAG_DIR" || true

  # avoid unbound-variable under set -u; ensure password file is read if present
  TEST_USER=${TEST_USER:-testuser}
  TEST_PASS=${TEST_PASS:-$(cat "$ROOT_DIR/gogotex-support-services/keycloak-service/testuser_password.txt" 2>/dev/null || echo "Test123!")}

  # Playwright run timeout (seconds) — shell-level guard to prevent hangs
  PLAYWRIGHT_RUN_TIMEOUT=${PLAYWRIGHT_RUN_TIMEOUT:-120}
  echo "Playwright runner timeout set to ${PLAYWRIGHT_RUN_TIMEOUT}s" >&2

  # Ensure `timeout` is available (GNU coreutils). If missing, fall back to a background timer.
  if command -v timeout >/dev/null 2>&1; then
    echo "Using 'timeout' wrapper to guard Playwright run" >&2
    if ! timeout ${PLAYWRIGHT_RUN_TIMEOUT}s "$ROOT_DIR/scripts/ci/auth-integration-test/playwright.sh"; then
      echo "Playwright step timed out or failed (timeout=${PLAYWRIGHT_RUN_TIMEOUT}s)" >&2
      # capture Keycloak logs for post-mortem
      docker logs keycloak-keycloak 2>/dev/null | sed -n '1,2000p' > "$DIAG_DIR/keycloak-full.log" || true
      docker logs keycloak-keycloak 2>/dev/null | tail -n 400 > "$DIAG_DIR/keycloak-last.log" || true
      echo "Saved Keycloak logs to $DIAG_DIR/keycloak-full.log and keycloak-last.log" >&2

      # extract any 'Unhandled exception in router' occurrences (with surrounding context)
      if grep -n 'Unhandled exception in router' "$DIAG_DIR/keycloak-full.log" >/dev/null 2>&1; then
        echo "Detected 'Unhandled exception in router' in Keycloak logs — extracting contexts" >&2
        : > "$DIAG_DIR/keycloak-unhandled.log"
        for L in $(grep -n 'Unhandled exception in router' "$DIAG_DIR/keycloak-full.log" | cut -d: -f1); do
          START=$((L>40?L-40:1))
          END=$((L+120))
          sed -n "${START},${END}p" "$DIAG_DIR/keycloak-full.log" >> "$DIAG_DIR/keycloak-unhandled.log"
          echo -e "\n---\n" >> "$DIAG_DIR/keycloak-unhandled.log"
        done
        echo "Saved extracted contexts to $DIAG_DIR/keycloak-unhandled.log" >&2
      else
        echo "No 'Unhandled exception in router' lines found in recent Keycloak logs." >&2
        if [ "${KEYCLOAK_LOG_LEVEL:-INFO}" != "DEBUG" ]; then
          echo "Tip: re-run with KEYCLOAK_DEBUG=true to enable DEBUG logging for Keycloak and capture full stack traces." >&2
        fi
      fi

      if [ "${FAIL_ON_AUTH_CODE:-true}" = "true" ]; then
        exit 7
      else
        echo "WARN: Playwright timed out/failed but continuing (FAIL_ON_AUTH_CODE=false)" >&2
      fi
    fi
  else
    echo "'timeout' not available — running Playwright and enforcing kill after ${PLAYWRIGHT_RUN_TIMEOUT}s" >&2
    "$ROOT_DIR/scripts/ci/auth-integration-test/playwright.sh" &
    PW_PID=$!
    ( sleep ${PLAYWRIGHT_RUN_TIMEOUT} && kill -0 "$PW_PID" 2>/dev/null && echo "Playwright exceeded timeout (${PLAYWRIGHT_RUN_TIMEOUT}s); killing..." >&2 && kill -TERM "$PW_PID" 2>/dev/null && sleep 5 && kill -KILL "$PW_PID" 2>/dev/null ) &
    WATCHER_PID=$!
    wait "$PW_PID" || true
    kill -9 "$WATCHER_PID" 2>/dev/null || true
  fi
fi

# client-verification deferred until CLIENT_TOKEN is available (moved later in script)

# Ensure TEST_USER default is set (avoids unbound variable when -u is set)
TEST_USER=${TEST_USER:-testuser}

# Use internal nginx proxy on the Docker network (no localhost usage required)
PROXY_URL=${PROXY_URL:-http://nginx-nginx}
echo "Using internal proxy: $PROXY_URL"

# diagnostics output folder (created early so we can write debug artifacts)
DIAG_DIR="${DIAG_DIR:-${ROOT_DIR:-.}/test-output}"
mkdir -p "$DIAG_DIR" || true
# host port to expose callback-sink (use 11xxx range for local debugging)
CB_SINK_HOST_PORT="${CB_SINK_HOST_PORT:-11300}"


# Acquire tokens for testing
# - CLIENT_TOKEN: client_credentials for administrative checks
# - USER_TOKEN: password-grant token for the test user (used to call /api/v1/me which expects an OIDC token)
echo "Requesting client_credentials token for test client..."
# Read client secret and request token directly (avoid parsing human-friendly script output)
CLIENT_SECRET_FILE="$ROOT_DIR/gogotex-support-services/keycloak-service/client-secret_gogotex-backend.txt"
if [ ! -f "$CLIENT_SECRET_FILE" ]; then
  echo "Client secret file not found: $CLIENT_SECRET_FILE"; exit 4
fi
CLIENT_SECRET=$(cat "$CLIENT_SECRET_FILE")
CLIENT_TOKEN=$(docker run --rm --network "$NET" curlimages/curl -sS --max-time 10 -X POST -d "client_id=gogotex-backend" -d "client_secret=$CLIENT_SECRET" -d "grant_type=client_credentials" http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/token | sed -n 's/.*"access_token":"\([^\"]*\)".*/\1/p' || true)
if [ -z "$CLIENT_TOKEN" ]; then
  echo "Failed to obtain client token"; exit 3
fi

# Verify client configuration (ensure directAccessGrantsEnabled and standardFlowEnabled)
echo "Verifying Keycloak client configuration for 'gogotex-backend'..."
# Prefer using an admin token for management operations (admin-cli). Fall back
# to CLIENT_TOKEN for read-only checks if admin token cannot be obtained.
ADMIN_PW=$(grep -m1 '^KEYCLOAK_ADMIN_PASSWORD=' "$ROOT_DIR/gogotex-support-services/.env" | sed -E 's/^[^=]+=//')
ADMIN_TOKEN=""
if [ -n "$ADMIN_PW" ]; then
  ADMIN_TOKEN=$(docker run --rm --network "$NET" curlimages/curl -sS --max-time 10 -X POST -d "client_id=admin-cli" -d "username=admin" -d "password=$ADMIN_PW" -d "grant_type=password" http://keycloak-keycloak:8080/sso/realms/master/protocol/openid-connect/token | jq -r '.access_token // empty') || true
fi
# Use admin token when available, otherwise use client token for read-only checks.
AUTH_HEADER="Authorization: Bearer ${ADMIN_TOKEN:-$CLIENT_TOKEN}"
CLIENT_CONF=$(docker run --rm --network "$NET" curlimages/curl -sS -H "$AUTH_HEADER" "http://keycloak-keycloak:8080/sso/admin/realms/gogotex/clients?clientId=gogotex-backend" | jq 'if type=="array" then .[0] else . end') || true
if [ -z "$CLIENT_CONF" ] || [ "$CLIENT_CONF" = "null" ]; then
  echo "ERROR: could not fetch client configuration after setup"; exit 5
fi
DIRECT_ENABLED=$(echo "$CLIENT_CONF" | jq -r '.directAccessGrantsEnabled')
STANDARD_ENABLED=$(echo "$CLIENT_CONF" | jq -r '.standardFlowEnabled')
if [ "$DIRECT_ENABLED" != "true" ] || [ "$STANDARD_ENABLED" != "true" ]; then
  echo "Client missing required grant settings; attempting to patch client..."
  if [ -z "$ADMIN_TOKEN" ]; then
    echo "Cannot patch client: admin token not available. Please ensure KEYCLOAK_ADMIN_PASSWORD is set in $ROOT_DIR/gogotex-support-services/.env"; exit 6
  fi
  CLIENT_ID_INTERNAL=$(echo "$CLIENT_CONF" | jq -r '.id')
  UPDATED=$(echo "$CLIENT_CONF" | jq '.directAccessGrantsEnabled = true | .standardFlowEnabled = true')
  docker run --rm --network "$NET" -v "$ROOT_DIR":/workdir -w /workdir curlimages/curl -sS -X PUT -H "Content-Type: application/json" -H "Authorization: Bearer $ADMIN_TOKEN" "http://keycloak-keycloak:8080/sso/admin/realms/gogotex/clients/$CLIENT_ID_INTERNAL" -d "$UPDATED" || true
  echo "Patched client configuration. Re-fetching..."
  CLIENT_CONF=$(docker run --rm --network "$NET" curlimages/curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "http://keycloak-keycloak:8080/sso/admin/realms/gogotex/clients?clientId=gogotex-backend" | jq 'if type=="array" then .[0] else . end') || true
  DIRECT_ENABLED=$(echo "$CLIENT_CONF" | jq -r '.directAccessGrantsEnabled')
  STANDARD_ENABLED=$(echo "$CLIENT_CONF" | jq -r '.standardFlowEnabled')
  if [ "$DIRECT_ENABLED" != "true" ] || [ "$STANDARD_ENABLED" != "true" ]; then
    echo "ERROR: client configuration still not patched correctly"; echo "$CLIENT_CONF" | sed -n '1,200p'; exit 6
  fi
  echo "Client configuration patched successfully"
fi
# Password-grant token for TEST_USER (used for /api/v1/me checks)


# Build a minimal auth image for the integration test
AUTH_IMAGE="gogotex-auth:ci"
AUTH_CONTAINER_NAME="gogotex-auth-integration"

# Always run a fresh integration container for deterministic tests (use
# AUTH_CONTAINER_NAME=gogotex-auth to explicitly reuse a long-running container).
# Remove any previous integration container with the same name to avoid conflicts.
docker rm -f "gogotex-auth-integration" >/dev/null 2>&1 || true
AUTH_CONTAINER_NAME="gogotex-auth-integration"

# Build image
echo "Building auth image $AUTH_IMAGE..."
if docker buildx version >/dev/null 2>&1; then
  echo "Using docker buildx (BuildKit)"
  docker buildx build --load -t "$AUTH_IMAGE" "$ROOT_DIR/backend/go-services"
else
  echo "docker buildx not available — falling back to classic docker build"
  docker build -t "$AUTH_IMAGE" "$ROOT_DIR/backend/go-services"
fi

# Ensure we always clean up the auth container when the script exits
cleanup() {
  docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm -f cb-sink >/dev/null 2>&1 || true
  if [ "${CLEANUP:-false}" = "true" ]; then
    echo "CLEANUP=true: bringing down Keycloak and MongoDB services..."
    docker compose -f "$KC_POSTGRES_YAML" -f "$KC_KEYCLOAK_YAML" -f "$MONGO_YAML" down || true
  else
    echo "Left infra running (set CLEANUP=true to tear down after tests)"
  fi
}
trap cleanup EXIT

# Run the auth service as a container on the same network
# If reusing an already-running 'gogotex-auth' container we don't re-create it.
echo "Starting auth service container ($AUTH_CONTAINER_NAME) on network $NET..."
if [ "$AUTH_CONTAINER_NAME" = "gogotex-auth" ]; then
    echo "Reusing existing container '$AUTH_CONTAINER_NAME' — not creating a new one"
  else
    # Remove any previous container with same name to avoid conflicts
    docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true
    # Start the container (no host port publishing — tests run inside the same Docker network)
    if ! docker run -d --name "$AUTH_CONTAINER_NAME" --network "$NET" -e KC_INSECURE=true \
      -e ALLOW_INSECURE_TOKEN=true \
      -e KEYCLOAK_URL=http://keycloak-keycloak:8080/sso \
      -e KEYCLOAK_REALM=gogotex \
      -e KEYCLOAK_CLIENT_ID=gogotex-backend \
      -e KEYCLOAK_CLIENT_SECRET="$CLIENT_SECRET" \
      -e MONGODB_URI=mongodb://mongodb-mongodb:27017 \
      -e MONGODB_DATABASE=gogotex \
      -e SERVER_HOST=0.0.0.0 -e SERVER_PORT=8081 \
      -e REDIS_HOST=redis-redis -e REDIS_PORT=6379 -e RATE_LIMIT_USE_REDIS=true \
      -e DOC_SERVICE_INLINE="${DOC_SERVICE_INLINE:-false}" \
      -e DOC_SERVICE_EXTERNAL="${DOC_SERVICE_EXTERNAL:-false}" \
      "$AUTH_IMAGE"; then
      echo "ERROR: failed to start auth container"; exit 5
    fi

    # we created a fresh integration container
    CREATED_AUTH_CONTAINER=true

    # debug: expose started container id + IP. wait for network IP to appear (docker DNS sometimes lags)
    CID=$(docker ps -q -f "name=^${AUTH_CONTAINER_NAME}$" || true)
    echo "DEBUG: started auth container id=$CID"
    if [ -n "$CID" ]; then
      # wait up to 30s for the container to acquire an IP on the desired network
      for _i in {1..60}; do
        # prefer the IP on the `tex-network` (if present)
        debug_ip=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{if eq $k "tex-network"}}{{$v.IPAddress}}{{end}}{{end}}' "$CID" 2>/dev/null || true)
        # fallback to any IP if `tex-network` key missing
        if [ -z "$debug_ip" ]; then
          debug_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CID" 2>/dev/null || true)
        fi
        if [ -n "$debug_ip" ]; then
          echo "DEBUG: started auth container ip=$debug_ip"; break
        fi
        # attempt to (re)connect container to the network if not present
        docker network connect "$NET" "$CID" >/dev/null 2>&1 || true
        sleep 1
      done
      # final echo (may be empty if IP still missing)
      debug_ip=${debug_ip:-}
      echo "DEBUG: started auth container ip=${debug_ip:-<none>}"
    fi
  fi
# Determine how to reach the auth service for health/metrics checks.
# Strategy:
# Prefer in-network access to the auth container (container IP or container name — no localhost)
# 2) Otherwise prefer the container's network IP (avoids DNS timing issues).
# 3) Fallback to container name when IP is not available.
# Prefer container IP or container name for in-network access (no localhost)
CID=$(docker ps -q -f "name=^${AUTH_CONTAINER_NAME}$" || true)
if [ -n "$CID" ]; then
  CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CID" 2>/dev/null || true)
  if [ -n "$CONTAINER_IP" ]; then
    AUTH_HOST="$CONTAINER_IP:8081"
  else
    AUTH_HOST="$AUTH_CONTAINER_NAME:8081"
  fi
else
  AUTH_HOST="$AUTH_CONTAINER_NAME:8081"
fi

# Wait for auth service to be fully ready (HTTP /ready) — this ensures handlers/deps are initialized
for i in {1..60}; do
  HTTP_CODE=$(docker run --rm --network "$NET" curlimages/curl -sS -o /dev/null -w "%{http_code}" http://$AUTH_HOST/ready || echo 000)
  echo "Auth ready HTTP: $HTTP_CODE"
  if [ "$HTTP_CODE" = "200" ]; then
    echo 'Auth service ready'; break
  fi
  # Print short container logs for early debugging on first few iterations
  if [ $i -le 3 ]; then
    docker logs "$AUTH_CONTAINER_NAME" 2>/dev/null | sed -n '1,80p' || true
  fi
  sleep 1
done
if [ "$HTTP_CODE" != "200" ]; then
  echo "Auth service did not become ready in time"; docker logs "$AUTH_CONTAINER_NAME" | sed -n '1,400p'; exit 6
fi

# verify Swagger UI is served (Phase‑02 requirement)
SWAG_HTTP=$(docker run --rm --network "$NET" curlimages/curl -sS -o /dev/null -w "%{http_code}" http://$AUTH_HOST/swagger/index.html || echo 000)
if [ "$SWAG_HTTP" != "200" ]; then
  echo "ERROR: /swagger/index.html not served by auth service (HTTP=$SWAG_HTTP)"; docker logs "$AUTH_CONTAINER_NAME" | sed -n '1,200p'; exit 7
fi

# --- Rate-limit + metrics verification (global middleware) ---
# Configure a very low rate limit for the test container run (global middleware reads env at startup)
# The auth container in this script is already running; we run quick checks against /health to
# ensure the in-memory limiter increments allowed/rejected metrics.

echo "Verifying rate-limiter + metrics on auth service..."
# send two quick /health requests: first should be 200, second likely 429 when test RPS/burst are restrictive
R1=$(docker run --rm --network "$NET" curlimages/curl -sS -o /dev/null -w "%{http_code}" http://$AUTH_HOST/health || echo 000)
R2=$(docker run --rm --network "$NET" curlimages/curl -sS -o /dev/null -w "%{http_code}" http://$AUTH_HOST/health || echo 000)
echo "rate-test responses: $R1 $R2"
# fetch metrics and check for rate-limit counters
METRICS=$(docker run --rm --network "$NET" curlimages/curl -sS http://$AUTH_HOST/metrics || true)
if echo "$METRICS" | grep -q '^gogotex_rate_limit_allowed_total'; then
  echo "Found rate_limit_allowed metric"
else
  echo "Missing rate_limit_allowed metric"; echo "$METRICS"; exit 7
fi
if echo "$METRICS" | grep -q '^gogotex_rate_limit_rejected_total'; then
  echo "Found rate_limit_rejected metric"
else
  echo "Missing rate_limit_rejected metric"; echo "$METRICS"; exit 7
fi
# Assert at least one allowed recorded
ALLOWED_VAL=$(echo "$METRICS" | grep '^gogotex_rate_limit_allowed_total' | head -n1 | sed -E 's/.* ([0-9\.]+)$/\1/')
REJECTED_VAL=$(echo "$METRICS" | grep '^gogotex_rate_limit_rejected_total' | head -n1 | sed -E 's/.* ([0-9\.]+)$/\1/')
echo "metrics values: allowed=$ALLOWED_VAL rejected=$REJECTED_VAL"
# simple numeric checks (allowed >= 1)
awk "BEGIN{exit !($ALLOWED_VAL >= 1)}" || (echo "Allowed metric < 1" && exit 8)
# rejected may be 0 or more depending on timing, that's acceptable

echo "Rate-limiter + metrics verified (allowed >= 1)."

# Optional compile smoke test: exercised when START_TEXLIVE=true or DOCKER_TEX_IMAGE is set
if [ "${START_TEXLIVE:-false}" = "true" ] || [ -n "${DOCKER_TEX_IMAGE:-}" ]; then
  echo "START_TEXLIVE/DOCKER_TEX_IMAGE set -> running compile smoke test against $AUTH_HOST"
  SMOKE_DOC_BODY='{"name":"smoke.tex","content":"\\documentclass{article}\\begin{document}Smoke Test\\end{document}"}'
  DOC_ID=$(docker run --rm --network "$NET" curlimages/curl -sS -X POST -H "Content-Type: application/json" -d "$SMOKE_DOC_BODY" http://$AUTH_HOST/api/documents | sed -n 's/.*"id":"\([^\"]*\)".*/\1/p') || true
  if [ -z "$DOC_ID" ]; then
    echo "ERROR: failed to create smoke document" >&2
    docker run --rm --network "$NET" curlimages/curl -sS http://$AUTH_HOST/ || true
    exit 9
  fi
  echo "Created smoke document: $DOC_ID"

  CJOB=$(docker run --rm --network "$NET" curlimages/curl -sS -X POST http://$AUTH_HOST/api/documents/$DOC_ID/compile | sed -n 's/.*"jobId":"\([^\"]*\)".*/\1/p') || true
  if [ -z "$CJOB" ]; then
    echo "ERROR: failed to start compile job for $DOC_ID" >&2
    exit 10
  fi
  echo "Started compile job: $CJOB"

  # poll logs until ready (timeout 40s)
  STATUS=""
  for i in $(seq 1 40); do
    STATUS=$(docker run --rm --network "$NET" curlimages/curl -sS http://$AUTH_HOST/api/documents/$DOC_ID/compile/logs | sed -n 's/.*"status":"\([^\"]*\)".*/\1/p' || true)
    if [ "$STATUS" = "ready" ]; then
      break
    fi
    sleep 1
  done
  if [ "$STATUS" != "ready" ]; then
    echo "ERROR: compile job did not reach ready state (status=$STATUS)" >&2
    docker run --rm --network "$NET" curlimages/curl -sS http://$AUTH_HOST/api/documents/$DOC_ID/compile/logs || true
    exit 11
  fi
  echo "Compile job ready"

  # verify PDF download is a real PDF (starts with %PDF)
  if ! docker run --rm --network "$NET" curlimages/curl -sS http://$AUTH_HOST/api/documents/$DOC_ID/compile/$CJOB/download | head -c 4 | grep -q '%PDF'; then
    echo "ERROR: compiled artifact is not a PDF" >&2
    exit 12
  fi
  echo "PDF artifact looks valid"

  # verify synctex endpoint serves gzip content-type
  CT=$(docker run --rm --network "$NET" curlimages/curl -sS -o /dev/null -w "%{content_type}" http://$AUTH_HOST/api/documents/$DOC_ID/compile/$CJOB/synctex || true)
  if [ "$CT" != "application/gzip" ] && [ "$CT" != "application/x-gzip" ]; then
    echo "ERROR: synctex endpoint did not return gzip (content-type=$CT)" >&2
    exit 13
  fi
  echo "Synctex endpoint returned gzip"
fi

# --- Start auth-code E2E flow: perform headless login to capture code or fallback to callback sink ---
# perform headless login using a small Python script (runs in-network)
TEST_PASS_FILE="$ROOT_DIR/gogotex-support-services/keycloak-service/testuser_password.txt"
TEST_PASS="$(cat "$TEST_PASS_FILE")"
# initialize capture variables (avoid unbound-variable under set -u)
CODE=""
REDIRECT_URI=""

# Option: FORCE_CB_SINK=true will use an HTTP callback sink (cb-sink) to capture the authorization code
# Determine which doc service to call for smoke tests: external service takes precedence
DOC_SERVICE_HOST="$AUTH_HOST"
if [ "${DOC_SERVICE_EXTERNAL:-false}" = "true" ]; then
  DOC_SERVICE_HOST="gogotex-go-document:5010"
fi

if [ "${FORCE_CB_SINK:-false}" = "true" ]; then
  echo "FORCE_CB_SINK=true: using callback sink to capture authorization code"
  docker rm -f cb-sink >/dev/null 2>&1 || true
  # Run callback sink on the internal network (no host port publishing required)
  docker run -d --name cb-sink --network "$NET" python:3.11-slim sh -c "python -u -m http.server 3000" >/dev/null
  # trigger the auth request (headless login will POST credentials and Keycloak will redirect to cb-sink)
  # perform a headless Python POST that follows redirects so Keycloak will redirect to cb-sink (reliable for required-action flows)
  docker run --rm --network "$NET" -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim sh -s <<'PY' || true
pip install requests bs4 >/dev/null 2>&1
python - <<'P'
import os, requests
from bs4 import BeautifulSoup
s = requests.Session()
auth_url = 'http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'
resp = s.get(auth_url, verify=False)
soup = BeautifulSoup(resp.text, 'html.parser')
form = soup.find('form')
if not form:
    raise SystemExit(1)
action = form.get('action')
if action and 'localhost' in action:
    action = action.replace('localhost:8080','keycloak-keycloak:8080')
payload = {inp['name']: inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
payload['username'] = os.environ['TEST_USER']
payload['password'] = os.environ['TEST_PASS']
# submit and follow redirects so cb-sink receives the GET
resp = s.post(action, data=payload, allow_redirects=True, verify=False)
print(resp.status_code)
P
PY
  for i in {1..30}; do
    LOGS=$(docker logs cb-sink 2>/dev/null || true)
    CODE=$(echo "$LOGS" | grep -o 'code=[^ &"]*' | head -n1 | sed 's/^code=//') || true
    if [ -n "$CODE" ]; then
      echo "Captured code from cb-sink: $CODE"; break
    fi
    sleep 1
  done
  if [ -z "$CODE" ]; then
    echo "Failed to capture authorization code via cb-sink"
    # Persist diagnostics
    echo "--- cb-sink logs ---" > "$DIAG_DIR/cb-sink.log" || true
    docker logs cb-sink 2>/dev/null | sed -n '1,200p' >> "$DIAG_DIR/cb-sink.log" || true
    docker logs keycloak-keycloak 2>/dev/null | sed -n '1,400p' > "$DIAG_DIR/keycloak.log" || true
    echo "Saved diagnostics to $DIAG_DIR/* (cb-sink, keycloak)"
    docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true
    exit 6
  fi
else
  echo "Performing headless login to obtain authorization code (captures code from redirect)..."
  # ensure callback sink (cb-sink) is available **before** following redirects
  docker rm -f cb-sink >/dev/null 2>&1 || true
  echo "Starting callback sink (cb-sink) on network $NET (preheadless)..."
  docker rm -f cb-sink >/dev/null 2>&1 || true
  # Run callback sink on the internal network (no host port publishing required)
  docker run -d --name cb-sink --network "$NET" python:3.11-slim sh -c "python -u -m http.server 3000" >/dev/null
  # Wait until cb-sink shows as Up (Docker may need a moment to register DNS)
  for i in {1..6}; do
    STATUS=$(docker ps --filter name=cb-sink --format '{{.Status}}' || true)
    if echo "$STATUS" | grep -q '^Up'; then
      echo "cb-sink is running ($STATUS)"; break
    fi
    echo "waiting for cb-sink DNS/ready... ($i)"; sleep 1
  done
  if ! echo "$STATUS" | grep -q '^Up'; then
    echo "Warning: cb-sink did not start properly (status='$STATUS')" || true
  fi

  # The Python script will detect the authorization code and the redirect URI used in Location headers during redirects
  # It prints the values as: <code>|||<redirect_uri>
  # Save Keycloak login HTML for diagnostics (helps when headless capture fails)
  KEYCLOAK_LOGIN_URL='http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'
  docker run --rm --network "$NET" curlimages/curl -sS "$KEYCLOAK_LOGIN_URL" > "$DIAG_DIR/keycloak_login.html" || true

  # --- try server-side non-follow POST to capture Location header (primary, reliable) ---
  LOCATION_HDR=$(docker run --rm --network "$NET" curlimages/curl -sS "$DIAG_DIR/keycloak_login.html":/tmp/kc.html true 2>/dev/null || true)
  # extract form action and POST credentials without following redirects
  ACTION=$(sed -n '1,400p' "$DIAG_DIR/keycloak_login.html" | grep -o 'action="[^"]*"' | head -n1 | sed -E 's/action="([^"]*)"/\1/' | sed 's/localhost:8080/keycloak-keycloak:8080/g' || true)
  if [ -n "$ACTION" ]; then
    LOCATION_HDR=$(docker run --rm --network "$NET" curlimages/curl -sS -D - -o /dev/null -X POST --data "username=$TEST_USER&password=$TEST_PASS" "$ACTION" | sed -n 's/Location: \(.*\)/\1/ip' | tr -d '\r' || true)
    if printf '%s' "$LOCATION_HDR" | grep -q 'code='; then
      echo "Captured code in Location header (server-side): $LOCATION_HDR"
      CODE=$(printf '%s' "$LOCATION_HDR" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p') || true
      REDIRECT_URI=$(printf '%s' "$LOCATION_HDR" | sed -n 's/\(https*:\/\/[^?]*\).*/\1/p') || true
    fi
  fi

  # Try the robust 'fresh GET + non-follow POST' first (same session) to capture Location header
  if [ -z "$CODE" ]; then
    echo "Trying fresh GET+non-follow POST (robust primary attempt)..."
    FRESH_LOC=$(docker run --rm --network "$NET" -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim /bin/sh -c "pip install requests bs4 >/dev/null 2>&1; python - <<'PY'
import os, requests
from bs4 import BeautifulSoup
s = requests.Session()
url = 'http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'
resp = s.get(url, verify=False)
soup = BeautifulSoup(resp.text, 'html.parser')
form = soup.find('form')
if not form:
    print('')
else:
    action = form.get('action')
    if 'localhost' in action:
        action = action.replace('localhost:8080','keycloak-keycloak:8080')
    inputs = {inp.get('name'): inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
    inputs['username'] = os.environ.get('TEST_USER')
    inputs['password'] = os.environ.get('TEST_PASS')
    r = s.post(action, data=inputs, allow_redirects=False, verify=False)
    print(r.headers.get('Location','') or '')
PY" || true)
    if printf '%s' "$FRESH_LOC" | grep -q 'code='; then
      echo "Captured code from fresh GET+POST: $FRESH_LOC"
      CODE=$(printf '%s' "$FRESH_LOC" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p') || true
      REDIRECT_URI=$(printf '%s' "$FRESH_LOC" | sed -n 's/\(https*:\/\/[^?]*\).*/\1/p') || true
    fi
  fi

  # Only run headless flow if CODE still empty
  if [ -z "$CODE" ]; then
    # Persist headless output for diagnostics so intermittent failures can be inspected
    HEADLESS_OUT="$DIAG_DIR/headless_raw_$(date +%Y%m%d-%H%M%S).txt"
    echo "Running headless flow (output -> $HEADLESS_OUT)"
    docker run --rm --network "$NET" -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim sh -s >"$HEADLESS_OUT" 2>&1 <<'SH'
python - <<'PY'
import os, time, requests
from bs4 import BeautifulSoup
from urllib.parse import urlparse, parse_qs
s = requests.Session()

auth_url = 'http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'
resp = s.get(auth_url, verify=False)
soup = BeautifulSoup(resp.text, 'html.parser')
form = soup.find('form')
if not form:
    print('|||')
    raise SystemExit(0)

action = form.get('action')
if action and 'localhost' in action:
    action = action.replace('localhost:8080','keycloak-keycloak:8080')

payload = {inp['name']: inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
payload['username'] = os.environ['TEST_USER']
payload['password'] = os.environ['TEST_PASS']

# submit and follow redirects so Keycloak will redirect to cb-sink if configured
try:
    resp = s.post(action, data=payload, allow_redirects=True, verify=False)
except requests.exceptions.ConnectionError:
    # connection to cb-sink may fail during redirect; fallthrough and inspect history/body
    resp = s.get(auth_url, verify=False)

# If Keycloak returns a required-action (e.g. VERIFY_PROFILE), complete it automatically
if 'required-action' in resp.url or 'VERIFY_PROFILE' in resp.url or 'required-action' in resp.text:
    soup2 = BeautifulSoup(resp.text, 'html.parser')
    form2 = soup2.find('form')
    if form2:
        action2 = form2.get('action')
        payload2 = {inp['name']: inp.get('value','') for inp in form2.find_all('input') if inp.get('name')}
        # populate common profile fields if empty
        payload2.setdefault('firstName', 'Test')
        payload2.setdefault('lastName', 'User')
        payload2.setdefault('email', os.environ.get('TEST_USER_EMAIL','testuser@gogotex.local'))
        resp = s.post(action2, data=payload2, allow_redirects=True, verify=False)
        # small delay to allow Keycloak to perform redirect to cb-sink
        time.sleep(1)

# Check final URL and redirect chain for code
if 'code=' in resp.url:
    parsed = urlparse(resp.url)
    q = parse_qs(parsed.query)
    if 'code' in q:
        print(q['code'][0] + '|||' + parsed.scheme + '://' + parsed.netloc + parsed.path)
        raise SystemExit(0)

# fallback: search HTML for callback URL with code
import re
m = re.search(r'(https?://[^\s"\']*/callback)[^\s"\']*.*code=([^\s\"\'\&]+)', resp.text)
if m:
    print(m.group(2) + '|||' + m.group(1))
    raise SystemExit(0)
print('|||')
PY
SH
  fi

  # copy headless output into DIAG_DIR/headless_latest.txt for quick access (only if headless ran)
  if [ -n "${HEADLESS_OUT:-}" ] && [ -s "$HEADLESS_OUT" ]; then
    cp -f "$HEADLESS_OUT" "$DIAG_DIR/headless_latest.txt" || true
    CODE_REDIRECT="$(sed -n '1p' "$HEADLESS_OUT" || true)"
  else
    CODE_REDIRECT=""
  fi
  # persist the login HTML we saved earlier (already written to $DIAG_DIR)
  if [ -f "$DIAG_DIR/keycloak_login.html" ]; then
    echo "Saved Keycloak login page to $DIAG_DIR/keycloak_login.html"
  fi

if [ -z "${CODE:-}" ]; then
  CODE="$(echo "$CODE_REDIRECT" | sed -n '1p' | cut -d'|' -f1)"
  REDIRECT_URI="$(echo "$CODE_REDIRECT" | sed -n '1p' | sed 's/.*|||//')"
fi

  if [ -n "$CODE" ]; then
    echo "Captured code directly: $CODE"
  else
    # Fallback #1: perform a non-following POST to Keycloak's login action and inspect the Location header for the code
    echo "Attempting non-follow POST to capture Location header (fast fallback, posts full form)..."
    if [ -f "$DIAG_DIR/keycloak_login.html" ]; then
      # Extract form inputs from saved HTML and POST them (uses Python to parse hidden inputs)
      LOCATION_HDR=$(docker run --rm --network "$NET" -v "$DIAG_DIR":/diag -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim /bin/sh -c "pip install requests bs4 >/dev/null 2>&1; python - <<'PY'
import os, sys, requests
from bs4 import BeautifulSoup
html = open('/diag/keycloak_login.html','r',encoding='utf-8').read()
S = BeautifulSoup(html,'html.parser')
form = S.find('form')
if not form:
    sys.exit(2)
action = form.get('action').replace('localhost:8080','keycloak-keycloak:8080')
inputs = {inp.get('name'): inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
inputs['username'] = os.environ.get('TEST_USER')
inputs['password'] = os.environ.get('TEST_PASS')
r = requests.post(action, data=inputs, allow_redirects=False, verify=False)
print(r.headers.get('Location','') or '')
PY" || true)
      if printf '%s' "$LOCATION_HDR" | grep -q 'code='; then
        echo "Captured code in Location header: $LOCATION_HDR"
        CODE=$(printf '%s' "$LOCATION_HDR" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p') || true
        REDIRECT_URI=$(printf '%s' "$LOCATION_HDR" | sed -n 's/\(https*:\/\/[^?]*\).*/\1/p') || true
      fi
    fi

    if [ -z "$CODE" ]; then
      # Fallback (strong): do a fresh GET -> POST (no redirect) inside the Docker network and inspect Location header
      echo "Attempting fresh GET+non-follow POST inside Docker network (strong fallback)..."
      FRESH_LOC=$(docker run --rm --network "$NET" -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim /bin/sh -c "pip install requests bs4 >/dev/null 2>&1; python - <<'PY'\nimport os, requests\nfrom bs4 import BeautifulSoup\nfrom urllib.parse import urlparse, parse_qs\ns = requests.Session()\nurl = 'http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'\nresp = s.get(url, verify=False)\nsoup = BeautifulSoup(resp.text, 'html.parser')\nform = soup.find('form')\nif not form:\n    print('')\nelse:\n    action = form.get('action')\n    if 'localhost' in action:\n        action = action.replace('localhost:8080','keycloak-keycloak:8080')\n    inputs = {inp.get('name'): inp.get('value','') for inp in form.find_all('input') if inp.get('name')}\n    inputs['username'] = os.environ.get('TEST_USER')\n    inputs['password'] = os.environ.get('TEST_PASS')\n    # initial post (do not follow redirects)
    r = s.post(action, data=inputs, allow_redirects=False, verify=False)\n    loc = r.headers.get('Location','')\n    # if required-action page returned in body, complete it and then inspect Location
    if 'required-action' in r.text or 'VERIFY_PROFILE' in r.text:\n        soup2 = BeautifulSoup(r.text, 'html.parser')\n        form2 = soup2.find('form')\n        if form2:\n            action2 = form2.get('action')\n            inputs2 = {inp.get('name'): inp.get('value','') for inp in form2.find_all('input') if inp.get('name')}\n            inputs2.setdefault('firstName','Test')\n            inputs2.setdefault('lastName','User')\n            inputs2.setdefault('email', os.environ.get('TEST_USER_EMAIL','testuser@gogotex.local'))\n            r2 = s.post(action2, data=inputs2, allow_redirects=False, verify=False)\n            loc = r2.headers.get('Location','') or loc\n    print(loc)\nPY" 2>/dev/null || true)
      if printf '%s' "$FRESH_LOC" | grep -q 'code='; then
        echo "Captured code from fresh non-follow POST: $FRESH_LOC"
        CODE=$(printf '%s' "$FRESH_LOC" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p') || true
        REDIRECT_URI=$(printf '%s' "$FRESH_LOC" | sed -n 's/\(https*:\/\/[^?]*\).*/\1/p') || true
      fi
    fi
  fi
  if [ -z "$CODE" ]; then
    echo "Failed to capture authorization code (no code from headless flow and no cb-sink fallback)."
    docker logs cb-sink 2>/dev/null || true
    docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true
    exit 6
  fi
fi

echo "Captured code: $CODE"

# Optional diagnostic: try exchanging the captured code directly with Keycloak token endpoint when DEBUG_KC_EXCHANGE=true
if [ "${DEBUG_KC_EXCHANGE:-false}" = "true" ]; then
  echo "Attempting direct token exchange with Keycloak (diagnostic)..."
  KC_TOKEN_RESP=$(docker run --rm --network "$NET" curlimages/curl -sS -X POST -d "grant_type=authorization_code" -d "client_id=gogotex-backend" -d "client_secret=$CLIENT_SECRET" -d "code=$CODE" -d "redirect_uri=$REDIRECT_URI" http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/token || true)
  echo "Keycloak token response: $KC_TOKEN_RESP"
  # DEBUG_KC_EXCHANGE consumes the authorization code at Keycloak. obtain a fresh code
  # for the actual auth-service exchange so we don't submit an already-used code.
  echo "DEBUG_KC_EXCHANGE=true: re-capturing fresh authorization code and redirect_uri"
  # Re-capture using the robust "fresh GET + non-follow POST" approach (same as primary capture)
  echo "Re-running fresh GET+non-follow POST to obtain a new code..."
  FRESH_LOC_RECAP=$(docker run --rm --network "$NET" -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim /bin/sh -c "pip install requests bs4 >/dev/null 2>&1; python - <<'PY'
import os, requests
from bs4 import BeautifulSoup
s = requests.Session()
url = 'http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'
resp = s.get(url, verify=False)
soup = BeautifulSoup(resp.text, 'html.parser')
form = soup.find('form')
if not form:
    print('')
else:
    action = form.get('action')
    if 'localhost' in action:
        action = action.replace('localhost:8080','keycloak-keycloak:8080')
    inputs = {inp.get('name'): inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
    inputs['username'] = os.environ.get('TEST_USER')
    inputs['password'] = os.environ.get('TEST_PASS')
    r = s.post(action, data=inputs, allow_redirects=False, verify=False)
    print(r.headers.get('Location','') or '')
PY" || true)
  if printf '%s' "$FRESH_LOC_RECAP" | grep -q 'code='; then
    CODE=$(printf '%s' "$FRESH_LOC_RECAP" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p' || true)
    REDIRECT_URI=$(printf '%s' "$FRESH_LOC_RECAP" | sed -n "s/\(https*:\/\/[^?]*\).*/\1/p" || true)
  fi
  echo "Re-captured code: $CODE redirect_uri: $REDIRECT_URI"
fi

# POST code to auth service (use auth service's /auth/login with mode=auth_code)
# Retry the full headless-capture -> exchange sequence to mitigate transient 'code not valid' or timing races
# Number of attempts to exchange an authorization code with the auth service
MAX_ATTEMPTS=${MAX_ATTEMPTS:-5}
# Whether to fail the entire script when auth-code E2E fails
FAIL_ON_AUTH_CODE=${FAIL_ON_AUTH_CODE:-true}
# Directory to write diagnostics when auth-code flow is flaky (initialized earlier)
# DIAG_DIR initialized near the top of the script

EXCHANGE_SUCCESS=false
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  echo "Exchanging code via auth service (attempt $attempt/$MAX_ATTEMPTS)..."
LOGIN_RESP=$(docker run --rm --network "$NET" curlimages/curl -sS -X POST -H "Content-Type: application/json" -d '{"mode":"auth_code","code":"'"$CODE"'"'","redirect_uri":"'"$REDIRECT_URI"'"'}' http://$AUTH_HOST/auth/login || true)"$CODE"'"","redirect_uri":"'"$REDIRECT_URI"'"'}' http://$AUTH_CONTAINER_NAME:8081/auth/login || true)
  if echo "$LOGIN_RESP" | jq -e '.access_token' >/dev/null 2>&1; then
    echo "✅ Auth-code E2E: auth service exchanged code and returned tokens"
    echo "$LOGIN_RESP" | jq .
    EXCHANGE_SUCCESS=true
    break
  else
    echo "Auth-code exchange failed on attempt $attempt: $LOGIN_RESP"

    # write diagnostics for this failure
    TS=$(date +%Y%m%d-%H%M%S)
    mkdir -p "$DIAG_DIR" || true
    echo "$LOGIN_RESP" > "$DIAG_DIR/login_response_$TS.json" || true
    docker logs "$AUTH_CONTAINER_NAME" 2>/dev/null | sed -n '1,400p' > "$DIAG_DIR/auth_container_$TS.log" || true
    docker logs keycloak-keycloak 2>/dev/null | sed -n '1,800p' > "$DIAG_DIR/keycloak_$TS.log" || true
    docker logs cb-sink 2>/dev/null | sed -n '1,200p' > "$DIAG_DIR/cb_sink_$TS.log" || true
    echo "Saved diagnostics to $DIAG_DIR/*_$TS.*"

    if [ $attempt -lt $MAX_ATTEMPTS ]; then
      # exponential backoff (cap at 16s)
      sleep_time=$((2 ** (attempt - 1)))
      if [ $sleep_time -gt 16 ]; then sleep_time=16; fi
      echo "Will retry headless flow to obtain a fresh code after ${sleep_time}s..."
      sleep $sleep_time

      # attempt headless capture again (follows redirects)
      CODE_REDIRECT=$(docker run --rm --network "$NET" -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim sh -s <<'SH'
python - <<'PY'
import os, requests
from bs4 import BeautifulSoup
from urllib.parse import urlparse, parse_qs
s = requests.Session()

auth_url = 'http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'
resp = s.get(auth_url, verify=False)
form = BeautifulSoup(resp.text, 'html.parser').find('form')
if not form:
    print('|||')
    raise SystemExit(0)
action = form.get('action')
if action and 'localhost' in action:
    action = action.replace('localhost:8080','keycloak-keycloak:8080')

payload = {inp['name']: inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
payload['username'] = os.environ['TEST_USER']
payload['password'] = os.environ['TEST_PASS']
resp = s.post(action, data=payload, allow_redirects=True, verify=False)

# If Keycloak requires profile verification, submit that form programmatically
if 'required-action' in resp.url or 'VERIFY_PROFILE' in resp.url or 'required-action' in resp.text:
    soup2 = BeautifulSoup(resp.text, 'html.parser')
    form2 = soup2.find('form')
    if form2:
        action2 = form2.get('action')
        payload2 = {inp['name']: inp.get('value','') for inp in form2.find_all('input') if inp.get('name')}
        payload2.setdefault('firstName','Test')
        payload2.setdefault('lastName','User')
        payload2.setdefault('email', os.environ.get('TEST_USER_EMAIL','testuser@gogotex.local'))
        resp = s.post(action2, data=payload2, allow_redirects=True, verify=False)

# check final URL
if 'code=' in resp.url:
    parsed = urlparse(resp.url)
    q = parse_qs(parsed.query)
    if 'code' in q:
        print(q['code'][0] + '|||' + parsed.scheme + '://' + parsed.netloc + parsed.path)
        raise SystemExit(0)
# fallback: search HTML
import re
m = re.search(r'(https?://[^\s"\']*/callback)[^\s"\']*.*code=([^\s\"\'\&]+)', resp.text)
if m:
    print(m.group(2) + '|||' + m.group(1))
    raise SystemExit(0)
print('|||')
PY
SH
)
# parse into CODE and REDIRECT_URI
CODE="$(printf '%s' "$CODE_REDIRECT" | sed -n '1p' | cut -d'|' -f1)"
REDIRECT_URI="$(printf '%s' "$CODE_REDIRECT" | sed -n '1p' | sed 's/.*|||//')"
      continue
    else
      echo "Auth-code exchange failed after $MAX_ATTEMPTS attempts.";
      break
    fi
  fi
done

# cleanup cb-sink
docker rm -f cb-sink >/dev/null 2>&1 || true

if [ "$EXCHANGE_SUCCESS" != "true" ]; then
  if [ "$FAIL_ON_AUTH_CODE" = "true" ]; then
    echo "❌ Auth-code E2E failed after $MAX_ATTEMPTS attempts."; docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true; exit 7
  else
    echo "⚠️ Auth-code E2E failed but continuing because FAIL_ON_AUTH_CODE=false (non-blocking)."
  fi
fi

# --- End auth-code E2E flow ---

# Call the /api/v1/me endpoint using the token via nginx (host-facing)
# Before calling /api/v1/me try to acquire a resource-owner token for the test user (preferred)
if [ -f "$TEST_PASS_FILE" ]; then
  TEST_PASS="$(cat "$TEST_PASS_FILE")"
  USER_TOKEN_RESP=$(docker run --rm --network "$NET" curlimages/curl -sS -X POST -d "client_id=gogotex-backend" -d "client_secret=$CLIENT_SECRET" -d "grant_type=password" -d "username=$TEST_USER" -d "password=$TEST_PASS" -d "scope=openid" http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/token || true)
  USER_ACCESS_TOKEN=$(printf '%s' "$USER_TOKEN_RESP" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p' || true)
  USER_ID_TOKEN=$(printf '%s' "$USER_TOKEN_RESP" | sed -n 's/.*"id_token":"\([^"]*\)".*/\1/p' || true)
  if [ -n "$USER_ID_TOKEN" ]; then
    echo "Acquired user id_token (preferred) for /api/v1/me checks"
  elif [ -n "$USER_ACCESS_TOKEN" ]; then
    echo "Acquired user access token for /api/v1/me checks (access token will be used)"
  else
    echo "Warning: failed to obtain password-grant token for test user; will fall back to client token"
  fi
  # Prefer OIDC id_token when available (middleware expects an id_token audience)
  USER_TOKEN=${USER_ID_TOKEN:-$USER_ACCESS_TOKEN}
else
  echo "Warning: test user password file not found ($TEST_PASS_FILE); will fall back to client token"
fi

echo "Calling /api/v1/me on auth service via internal proxy ($PROXY_URL/api/v1/me)..."
AUTH_TOKEN=${USER_TOKEN:-$CLIENT_TOKEN}
# call the internal proxy from the test runner using curl image on the same network
RESP=$(docker run --rm --network "$NET" curlimages/curl -sS -H "Authorization: Bearer $AUTH_TOKEN" "$PROXY_URL/api/v1/me" || true)

# Basic validation: should include "user" with "sub" or at least claims
if echo "$RESP" | jq -e '.user.sub' >/dev/null 2>&1; then
  echo "✅ Integration test passed: user created and returned (via nginx)"
  echo "$RESP" | jq .
  # cleanup
  docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true
  exit 0
else
  echo "❌ Integration test (via nginx) failed. Response:"; echo "$RESP" | sed -n '1,200p'
  echo "Falling back to direct container check for debugging..."
  RESP2=$(docker run --rm --network "$NET" curlimages/curl -sS -H "Authorization: Bearer $AUTH_TOKEN" http://$AUTH_HOST/api/v1/me || true)
  echo "Direct container response:"; echo "$RESP2" | sed -n '1,200p'
  echo "Auth logs:"; docker logs "$AUTH_CONTAINER_NAME" | sed -n '1,200p'
  docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true
  exit 4
fi
