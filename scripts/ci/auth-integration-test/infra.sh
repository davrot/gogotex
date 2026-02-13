#!/usr/bin/env bash
set -euo pipefail

# Bring up Keycloak + Mongo (idempotent) and wait until Keycloak HTTP responds.
# Prints the Docker network name on success.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
KC_POSTGRES_YAML="$ROOT_DIR/gogotex-support-services/keycloak-service/keycloak-postgres.yaml"
KC_KEYCLOAK_YAML="$ROOT_DIR/gogotex-support-services/keycloak-service/keycloak.yaml"
MONGO_YAML="$ROOT_DIR/gogotex-support-services/mongodb-service/mongodb.yaml"

# Bring up Keycloak and MongoDB (robust: only bring up missing services)
KC_PRESENT=$(docker ps --format '{{.Names}}' | grep -q '^keycloak-keycloak$' && echo yes || echo no)
MONGO_PRESENT=$(docker ps --format '{{.Names}}' | grep -q '^mongodb-mongodb$' && echo yes || echo no)
if [ "$KC_PRESENT" = "yes" ] && [ "$MONGO_PRESENT" = "yes" ]; then
  echo "Keycloak and MongoDB containers already present; skipping docker compose up" >&2
else
  echo "Bringing up missing infra services..." >&2
  if [ "$KC_PRESENT" = "no" ] && [ "$MONGO_PRESENT" = "no" ]; then
    docker compose -f "$KC_POSTGRES_YAML" -f "$KC_KEYCLOAK_YAML" -f "$MONGO_YAML" up -d >/dev/null 2>&1 || true
  elif [ "$KC_PRESENT" = "no" ] && [ "$MONGO_PRESENT" = "yes" ]; then
    docker compose -f "$KC_POSTGRES_YAML" -f "$KC_KEYCLOAK_YAML" up -d >/dev/null 2>&1 || true
  else
    echo "No infra changes required" >&2
  fi
fi

# Wait for keycloak container
for i in {1..60}; do
  if docker ps --format '{{.Names}}' | grep -q '^keycloak-keycloak$'; then
    echo "Keycloak container present" >&2; break
  fi
  sleep 1
done

# detect the Docker network that Keycloak is attached to and return it
NET=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' keycloak-keycloak 2>/dev/null || true)
if [ -z "$NET" ]; then
  # print nothing to stdout (caller expects only the network on stdout)
  echo "" >&2
  exit 2
fi

# Wait for Keycloak HTTP to respond (configurable timeout & per-request curl timeout)
# Environment overrides: KEYCLOAK_HTTP_WAIT_SECS (total wait, default 120), KEYCLOAK_POLL_INTERVAL (seconds, default 2), KEYCLOAK_CURL_TIMEOUT (per-request curl --max-time, default 5)
KEYCLOAK_HTTP_WAIT_SECS=${KEYCLOAK_HTTP_WAIT_SECS:-120}
KEYCLOAK_POLL_INTERVAL=${KEYCLOAK_POLL_INTERVAL:-2}
KEYCLOAK_CURL_TIMEOUT=${KEYCLOAK_CURL_TIMEOUT:-5}
MAX_TRIES=$(( (KEYCLOAK_HTTP_WAIT_SECS + KEYCLOAK_POLL_INTERVAL - 1) / KEYCLOAK_POLL_INTERVAL ))

for i in $(seq 1 "$MAX_TRIES"); do
  HTTP_CODE=$(docker run --rm --network "$NET" curlimages/curl -sS --max-time "$KEYCLOAK_CURL_TIMEOUT" -o /dev/null -w "%{http_code}" http://keycloak-keycloak:8080/sso/ 2>/dev/null || echo 000)
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "400" ]; then
    echo "Keycloak HTTP response: $HTTP_CODE" >&2; break
  fi
  echo -n '.' >&2; sleep "$KEYCLOAK_POLL_INTERVAL"
done
if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "302" ] && [ "$HTTP_CODE" != "401" ] && [ "$HTTP_CODE" != "400" ]; then
  echo "ERROR: Keycloak did not become reachable within ${KEYCLOAK_HTTP_WAIT_SECS}s (last_http_code=$HTTP_CODE)" >&2
  echo "Tip: inspect 'docker ps -a' and 'docker logs keycloak-keycloak' for details" >&2
  exit 2
fi

# return the network name to caller (stdout only contains the network)
printf "%s" "$NET"
