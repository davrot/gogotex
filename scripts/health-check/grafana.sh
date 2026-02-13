# Grafana UI check (sourced by scripts/health-check.sh)
# Standalone bootstrap: provide ok/fail helpers and load .env
if ! declare -f ok >/dev/null 2>&1; then
  ok(){ echo "✅ $1"; PASSED=${PASSED:-0}; PASSED=$((PASSED+1)); }
fi
if ! declare -f fail >/dev/null 2>&1; then
  fail(){ echo "❌ $1"; FAILED=${FAILED:-0}; FAILED=$((FAILED+1)); }
fi
ROOT_DIR=${ROOT_DIR:-"$(cd "$(dirname "$0")/../.." && pwd)"}
CONTAINERS=${CONTAINERS:-$(docker ps --format '{{.Names}}' 2>/dev/null || true)}
GRAF_C=${GRAF_C:-grafana-grafana}

# expects: GRAF_C variable and ok/fail helpers

echo
echo "== Grafana quick check =="
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
else
  echo "- Skipping Grafana check (container missing)"
fi
