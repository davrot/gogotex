# Prometheus HTTP/API check (sourced by scripts/health-check.sh)
# Standalone bootstrap: provide ok/fail helpers and load .env
if ! declare -f ok >/dev/null 2>&1; then
  ok(){ echo "✅ $1"; PASSED=${PASSED:-0}; PASSED=$((PASSED+1)); }
fi
if ! declare -f fail >/dev/null 2>&1; then
  fail(){ echo "❌ $1"; FAILED=${FAILED:-0}; FAILED=$((FAILED+1)); }
fi
ROOT_DIR=${ROOT_DIR:-"$(cd "$(dirname "$0")/../.." && pwd)"}
CONTAINERS=${CONTAINERS:-$(docker ps --format '{{.Names}}' 2>/dev/null || true)}
PROM_C=${PROM_C:-grafana-prometheus}

echo
echo "== Prometheus quick check =="
if [ -n "$PROM_C" ]; then
  # try host port 9090 (if published) then internal network
  set +e
  HOST_CODE=$(curl -sS -o /dev/null -w "%{http_code}" http://localhost:9090/ 2>/dev/null || true)
  if [ "$HOST_CODE" != "000" ]; then
    CODE="$HOST_CODE"
  else
    CODE=$(docker run --rm --network tex-network curlimages/curl:8.4.0 -sS -o /dev/null -w "%{http_code}" http://grafana-prometheus:9090/ || true)
  fi
  set -e

  if [ "$CODE" = "200" ] || [ "$CODE" = "302" ]; then
    ok "Prometheus HTTP UI reachable (code $CODE)"
  else
    fail "Prometheus UI not reachable (code: $CODE)"
  fi

  # API runtime info check
  set +e
  RCODE=$(docker run --rm --network tex-network curlimages/curl:8.4.0 -sS -f -o /dev/null -w "%{http_code}" http://grafana-prometheus:9090/api/v1/status/runtimeinfo || true)
  set -e
  if [ "$RCODE" = "200" ]; then
    ok "Prometheus API /api/v1/status/runtimeinfo reachable"
  else
    fail "Prometheus API check failed (code: $RCODE)"
  fi
else
  echo "- Skipping Prometheus check (container missing)"
fi