#!/usr/bin/env bash
set -euo pipefail

# scripts/health-check.sh
# Basic infrastructure health checks for Phase 1

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# If not already running inside the helper Docker runner, re-exec this script
# inside an Ubuntu container attached to the `tex-network` so internal container
# hostnames (e.g. keycloak-keycloak, mongodb-mongodb) resolve reliably.
if [ "${HEALTH_CHECK_IN_DOCKER:-}" != "1" ]; then
  echo "Re-running health checks inside ephemeral Ubuntu container on network 'tex-network'..."
  docker run --rm -v "$ROOT_DIR":"$ROOT_DIR" -w "$ROOT_DIR" -v /var/run/docker.sock:/var/run/docker.sock --network tex-network ubuntu:24.04 \
    bash -lc "set -euo pipefail; export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null; apt-get install -y -qq docker.io curl jq bash >/dev/null; HEALTH_CHECK_IN_DOCKER=1 bash '$ROOT_DIR/scripts/health-check.sh' \"$@\""
  exit $?
fi

SUPPORT_DIR="$ROOT_DIR/gogotex-support-services"
KEYCLOAK_SECRET_FILE="$SUPPORT_DIR/keycloak-service/client-secret_gogotex-backend.txt"
KEYCLOAK_USER="admin"
# load .env if exists
if [ -f "$SUPPORT_DIR/.env" ]; then
  # shellcheck disable=SC1091
  set -o allexport
  source "$SUPPORT_DIR/.env"
  set +o allexport
fi
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-changeme_keycloak}
REDIS_PASSWORD=${REDIS_PASSWORD:-changeme_redis}

PASSED=0
FAILED=0

ok() { echo "✅ $1"; PASSED=$((PASSED+1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED+1)); }

echo "== Basic Docker / containers check =="
if docker info >/dev/null 2>&1; then
  ok "Docker daemon reachable"
else
  fail "Docker daemon not reachable"
fi

CONTAINERS=$(docker ps --format '{{.Names}}')
# helper to find container by regex - prefers specific service names when possible
find_container() {
  echo "$CONTAINERS" | grep -E "$1" | grep -v -E "exporter|healthcheck" | head -n1 || true
}

# Key services to look for (prefer exact or typical service names)
KEYCLOAK_C=$(find_container "(^keycloak-keycloak$|keycloak|gogotex-keycloak)")
MONGO_C=$(find_container "(^mongodb-mongodb$|mongo|mongodb)")
# Prefer 'redis-redis' to avoid matching exporter containers
REDIS_C=$(find_container "(^redis-redis$|redis)")
MINIO_C=$(find_container "(^minio-minio$|minio)")
PROM_C=$(find_container "(^grafana-prometheus$|prometheus|prom)")
GRAF_C=$(find_container "(^grafana-grafana$|grafana)")
NGINX_C=$(find_container "(^nginx-nginx$|nginx)")

if [ -n "$KEYCLOAK_C" ]; then ok "Found Keycloak container: $KEYCLOAK_C"; else fail "Keycloak container not found"; fi
if [ -n "$MONGO_C" ]; then ok "Found MongoDB container: $MONGO_C"; else fail "MongoDB container not found"; fi
if [ -n "$REDIS_C" ]; then ok "Found Redis container: $REDIS_C"; else fail "Redis container not found"; fi
if [ -n "$MINIO_C" ]; then ok "Found MinIO container: $MINIO_C"; else fail "MinIO container not found"; fi
if [ -n "$PROM_C" ]; then ok "Found Prometheus container: $PROM_C"; else fail "Prometheus container not found"; fi
if [ -n "$GRAF_C" ]; then ok "Found Grafana container: $GRAF_C"; else fail "Grafana container not found"; fi
if [ -n "$NGINX_C" ]; then ok "Found nginx container: $NGINX_C"; else fail "nginx container not found"; fi

echo
echo "== Keycloak checks =="
# check token endpoint on localhost (nginx proxy) first, fallback to container network
KC_URLS=("https://localhost/sso" "http://localhost:8080/sso" "http://keycloak-keycloak:8080/sso" "http://gogotex-keycloak:8080/sso")
KC_TOKEN=""
for base in "${KC_URLS[@]}"; do
  echo -n "- Testing token endpoint at $base ... "
  set +e
  # allow insecure for localhost https
  TOKEN_RESP=$(curl -k -sS -X POST "$base/realms/master/protocol/openid-connect/token" -d "grant_type=password&client_id=admin-cli&username=$KEYCLOAK_USER&password=$KEYCLOAK_ADMIN_PASSWORD" 2>/dev/null)
  set -e
  if echo "$TOKEN_RESP" | jq -e '.access_token' >/dev/null 2>&1; then
    KC_TOKEN=$(echo "$TOKEN_RESP" | jq -r .access_token)
    ok "Keycloak admin token available at $base"
    KC_BASE="$base"
    break
  else
    echo "no token"
  fi
done

if [ -n "$KC_TOKEN" ]; then
  # verify our client secret file exists and works via client_credentials
  if [ -f "$KEYCLOAK_SECRET_FILE" ]; then
    CLIENT_SECRET=$(cat "$KEYCLOAK_SECRET_FILE")
    echo -n "- Testing client_credentials for gogotex-backend ... "
    CC_RESP=$(curl -k -sS -X POST "$KC_BASE/realms/gogotex/protocol/openid-connect/token" -d "grant_type=client_credentials&client_id=gogotex-backend&client_secret=$CLIENT_SECRET" || true)
    if echo "$CC_RESP" | jq -e '.access_token' >/dev/null 2>&1; then
      ok "Client credentials flow works"
    else
      fail "Client credentials flow failed (response: $(echo "$CC_RESP" | tr -d '\n' | sed -n '1,200p'))"
    fi
  else
    fail "Client secret file missing: $KEYCLOAK_SECRET_FILE"
  fi
else
  fail "Cannot obtain Keycloak admin token from any candidate host"
fi

echo
echo "== MongoDB checks =="
if [ -n "$MONGO_C" ]; then
  set +e
  ping_resp=$(docker exec -i "$MONGO_C" mongosh --eval 'db.adminCommand({ping:1})' --quiet 2>/dev/null || true)
  set -e
  if echo "$ping_resp" | grep -q "ok"; then
    ok "MongoDB ping OK"
    # check gogotex DB exists
    exists=$(docker exec -i "$MONGO_C" mongosh --eval 'db.getMongo().getDBNames()' --quiet 2>/dev/null || true)
    if echo "$exists" | grep -q "gogotex"; then
      ok "gogotex database present"
    else
      fail "gogotex database not found"
    fi
  else
    fail "MongoDB ping failed"
  fi
else
  echo "- Skipping MongoDB checks (container missing)"
fi

echo
echo "== Redis checks =="
if [ -n "$REDIS_C" ]; then
  set +e
  # if the chosen container does not have redis-cli, try the canonical redis container
  if ! docker exec -i "$REDIS_C" sh -c "command -v redis-cli >/dev/null 2>&1"; then
    if echo "$CONTAINERS" | grep -xq "redis-redis"; then
      REDIS_C="redis-redis"
      echo "- Switched to canonical redis container: $REDIS_C"
    fi
  fi

  PONG=""
  if docker exec -i "$REDIS_C" sh -c "command -v redis-cli >/dev/null 2>&1"; then
    PONG=$(docker exec -i "$REDIS_C" redis-cli -a "$REDIS_PASSWORD" PING 2>/dev/null || true)
  else
    # fallback: use ephemeral redis image and connect to host port 6379
    PONG=$(docker run --rm --network host redis:8.4-alpine redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PASSWORD" PING 2>/dev/null || true) || true
  fi
  set -e
  if [ "$PONG" = "PONG" ]; then
    ok "Redis PING OK"
    # test set/get if container supports redis-cli
    if docker exec -i "$REDIS_C" sh -c "command -v redis-cli >/dev/null 2>&1"; then
      docker exec -i "$REDIS_C" redis-cli -a "$REDIS_PASSWORD" SET healthcheck_key "ok" >/dev/null 2>&1 || true
      GOT=$(docker exec -i "$REDIS_C" redis-cli -a "$REDIS_PASSWORD" GET healthcheck_key 2>/dev/null || true)
      if [ "$GOT" = "ok" ]; then ok "Redis SET/GET OK"; else fail "Redis SET/GET failed"; fi
    else
      ok "Redis appears reachable (SET/GET not tested inside container)"
    fi
  else
    fail "Redis PING failed (response: $PONG)"
  fi
else
  echo "- Skipping Redis checks (container missing)"
fi

echo
echo "== MinIO checks =="
if [ -n "$MINIO_C" ]; then
  # Prefer the unauthenticated health endpoint (explicitly checks service liveness)
  set +e
  HEALTH_CODE=$(docker run --rm --network tex-network curlimages/curl:8.4.0 -sS -o /dev/null -w "%{http_code}" http://minio-minio:9000/minio/health/live || true)
  set -e
  if [ "$HEALTH_CODE" = "200" ]; then
    ok "MinIO health endpoint OK (/minio/health/live)"
  else
    # fallback: root may return 403 for anonymous access — treat 403 as "service up, auth required"
    ROOT_CODE=$(docker run --rm --network tex-network curlimages/curl:8.4.0 -sS -o /dev/null -w "%{http_code}" http://minio-minio:9000/ || true)
    if [ "$ROOT_CODE" = "403" ]; then
      ok "MinIO HTTP endpoint responded (code 403 — anonymous access restricted)"
    elif [ "$ROOT_CODE" != "000" ]; then
      ok "MinIO HTTP endpoint responded (code $ROOT_CODE)"
    else
      fail "MinIO endpoint not responding on http://minio-minio:9000/"
    fi
  fi

  # --- authenticated checks: verify credentials and optional bucket presence ---
  MINIO_USER=${MINIO_ROOT_USER:-${MINIO_ACCESS_KEY:-admin}}
  MINIO_PASS=${MINIO_ROOT_PASSWORD:-${MINIO_SECRET_KEY:-changeme_minio}}

  set +e
  docker run --rm --network tex-network --entrypoint /bin/sh minio/mc -c "mc alias set tmp http://minio-minio:9000 $MINIO_USER $MINIO_PASS >/dev/null 2>&1 && mc ls tmp >/dev/null 2>&1"
  AUTH_OK=$?
  set -e

  if [ $AUTH_OK -eq 0 ]; then
    ok "MinIO authenticated API reachable (credentials valid)"

    # If MINIO_BUCKET is configured, ensure it exists
    if [ -n "${MINIO_BUCKET:-}" ]; then
      set +e
      docker run --rm --network tex-network --entrypoint /bin/sh minio/mc -c "mc alias set tmp http://minio-minio:9000 $MINIO_USER $MINIO_PASS >/dev/null 2>&1 && mc ls tmp/${MINIO_BUCKET} >/dev/null 2>&1"
      BUCKET_OK=$?
      set -e
      if [ $BUCKET_OK -eq 0 ]; then
        ok "MinIO bucket '${MINIO_BUCKET}' present"
      else
        fail "MinIO bucket '${MINIO_BUCKET}' not found"
      fi
    fi
  else
    fail "MinIO authentication failed with provided credentials"
  fi
else
  echo "- Skipping MinIO checks (container missing)"
fi

echo
echo "== Prometheus / Grafana quick checks =="
if [ -n "$PROM_C" ]; then
  ok "Prometheus container present: $PROM_C"
fi
if [ -n "$GRAF_C" ]; then
  # try Grafana UI on common host ports, then try internal network
  GCODE=$(curl -sS -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || true)
  if [ "$GCODE" = "000" ]; then
    GCODE=$(curl -sS -o /dev/null -w "%{http_code}" http://localhost:3001/ 2>/dev/null || true)
  fi
  if [ "$GCODE" = "000" ]; then
    # try internal network (requires curl image available)
    set +e
    NETCODE=$(docker run --rm --network tex-network curlimages/curl:8.4.0 -sS -o /dev/null -w "%{http_code}" http://grafana-grafana:3000/ || true)
    set -e
    if [ "$NETCODE" = "302" ] || [ "$NETCODE" = "200" ]; then
      ok "Grafana UI responded on internal network (code $NETCODE)"
    else
      fail "Grafana UI not responding on localhost:3000/3001 or internal network"
    fi
  else
    ok "Grafana UI responded (code $GCODE)"
  fi
fi

echo
echo "== nginx quick check =="
if [ -n "$NGINX_C" ]; then
  NCODE=$(curl -sS -o /dev/null -w "%{http_code}" http://localhost/ || true)
  if [ "$NCODE" = "000" ]; then
    fail "nginx not responding on http://localhost/"
  else
    ok "nginx responded (code $NCODE)"
  fi
fi


# Summary
echo
echo "== Summary: Passed=$PASSED Failed=$FAILED =="
if [ $FAILED -gt 0 ]; then
  echo "Some checks failed. Please inspect the output above and fix issues."
  exit 2
else
  echo "All checks passed"
  exit 0
fi
