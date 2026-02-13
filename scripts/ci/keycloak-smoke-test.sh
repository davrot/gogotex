#!/usr/bin/env bash
set -euo pipefail

# Load environment from support .env if present
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$SCRIPT_DIR"
SUPPORT_ENV="$ROOT_DIR/gogotex-support-services/.env"
if [ -f "$SUPPORT_ENV" ]; then
  set -o allexport
  source "$SUPPORT_ENV"
  set +o allexport
fi

# CI smoke test script
# - Brings up Keycloak + Postgres via docker compose for the keycloak-service
# - Waits until Keycloak responds to token endpoint requests
# - Runs the keycloak setup script inside an ephemeral container on the compose network
# - Runs the keycloak-test-client script to verify token issuance

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KC_POSTGRES_YAML="$ROOT/gogotex-support-services/keycloak-service/keycloak-postgres.yaml"
KC_KEYCLOAK_YAML="$ROOT/gogotex-support-services/keycloak-service/keycloak.yaml"

echo "Starting Keycloak Postgres and Keycloak containers..."
docker compose -f "$KC_POSTGRES_YAML" -f "$KC_KEYCLOAK_YAML" up -d

# Wait for the keycloak container to appear
echo "Waiting for keycloak container to be visible..."
for i in {1..30}; do
  if docker ps --format '{{.Names}}' | grep -q '^keycloak-keycloak$'; then
    echo "Keycloak container present"; break
  fi
  sleep 1
done

# Get the network name used by the keycloak container
NET=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' keycloak-keycloak)
if [ -z "$NET" ]; then
  echo "ERROR: could not detect Docker network for keycloak-keycloak" >&2
  exit 2
fi

# Wait for Keycloak token endpoint to respond with something other than 404/empty
# Configurable: KEYCLOAK_HTTP_WAIT_SECS, KEYCLOAK_POLL_INTERVAL, KEYCLOAK_CURL_TIMEOUT
KEYCLOAK_HTTP_WAIT_SECS=${KEYCLOAK_HTTP_WAIT_SECS:-120}
KEYCLOAK_POLL_INTERVAL=${KEYCLOAK_POLL_INTERVAL:-2}
KEYCLOAK_CURL_TIMEOUT=${KEYCLOAK_CURL_TIMEOUT:-5}
MAX_TRIES=$(( (KEYCLOAK_HTTP_WAIT_SECS + KEYCLOAK_POLL_INTERVAL - 1) / KEYCLOAK_POLL_INTERVAL ))

echo "Waiting for Keycloak to be ready (token endpoint) on network $NET..."
for i in $(seq 1 "$MAX_TRIES"); do
  HTTP_CODE=$(docker run --rm --network "$NET" curlimages/curl -sS --max-time "$KEYCLOAK_CURL_TIMEOUT" -o /dev/null -w "%{http_code}" http://keycloak-keycloak:8080/sso/ 2>/dev/null || echo 000)
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "400" ]; then
    echo "Keycloak HTTP response: $HTTP_CODE"; break
  fi
  echo -n '.'; sleep "$KEYCLOAK_POLL_INTERVAL"
done
if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "302" ] && [ "$HTTP_CODE" != "401" ] && [ "$HTTP_CODE" != "400" ]; then
  echo "ERROR: Keycloak did not become reachable within ${KEYCLOAK_HTTP_WAIT_SECS}s (last_http_code=$HTTP_CODE)" >&2
  exit 2
fi

# Run the setup script inside the Docker network
echo "Running keycloak setup script inside ephemeral container..."
docker run --rm --network "$NET" -v "$ROOT":/workdir -w /workdir alpine:3.19 sh -c "apk add --no-cache curl jq openssl bash >/dev/null 2>&1 && KC_INSECURE=false KC_HOST=http://keycloak-keycloak:8080/sso /workdir/scripts/keycloak-setup.sh"

# Run the test client to verify token issuance
echo "Running keycloak test client (client_credentials mode)..."
docker run --rm --network "$NET" -v "$ROOT":/workdir -w /workdir alpine:3.19 sh -c "apk add --no-cache curl jq openssl bash >/dev/null 2>&1 && chmod +x /workdir/scripts/keycloak-test-client.sh && /workdir/scripts/keycloak-test-client.sh --mode client_credentials --kc-host http://keycloak-keycloak:8080/sso --client-id gogotex-backend --secret-file /workdir/gogotex-support-services/keycloak-service/client-secret_gogotex-backend.txt"

# Note: If the script reaches here without error, it's a success
exit 0
