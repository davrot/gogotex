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
  echo "Keycloak and MongoDB containers already present; skipping docker compose up"
else
  echo "Bringing up missing infra services..."
  if [ "$KC_PRESENT" = "no" ] && [ "$MONGO_PRESENT" = "no" ]; then
    docker compose -f "$KC_POSTGRES_YAML" -f "$KC_KEYCLOAK_YAML" -f "$MONGO_YAML" up -d || true
  elif [ "$KC_PRESENT" = "no" ] && [ "$MONGO_PRESENT" = "yes" ]; then
    docker compose -f "$KC_POSTGRES_YAML" -f "$KC_KEYCLOAK_YAML" up -d || true
  else
    echo "No infra changes required"
  fi
fi

# Wait for keycloak container
for i in {1..60}; do
  if docker ps --format '{{.Names}}' | grep -q '^keycloak-keycloak$'; then
    echo "Keycloak container present"; break
  fi
  sleep 1
done

# detect the Docker network that Keycloak is attached to and return it
NET=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' keycloak-keycloak 2>/dev/null || true)
if [ -z "$NET" ]; then
  echo "" # print empty to caller (will be treated as error)
  exit 2
fi

# Wait for Keycloak HTTP to respond
for i in {1..120}; do
  HTTP_CODE=$(docker run --rm --network "$NET" curlimages/curl -sS -o /dev/null -w "%{http_code}" http://keycloak-keycloak:8080/sso/ || echo 000)
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "400" ]; then
    echo "Keycloak HTTP response: $HTTP_CODE"; break
  fi
  echo -n '.'; sleep 2
done

# return the network name to caller
printf "%s" "$NET"
