# MongoDB checks (sourced by scripts/health-check.sh)
# Standalone bootstrap: provide ok/fail helpers, load .env and sensible defaults.
if ! declare -f ok >/dev/null 2>&1; then
  ok(){ echo "✅ $1"; PASSED=${PASSED:-0}; PASSED=$((PASSED+1)); }
fi
if ! declare -f fail >/dev/null 2>&1; then
  fail(){ echo "❌ $1"; FAILED=${FAILED:-0}; FAILED=$((FAILED+1)); }
fi
ROOT_DIR=${ROOT_DIR:-"$(cd "$(dirname "$0")/../.." && pwd)"}
CONTAINERS=${CONTAINERS:-$(docker ps --format '{{.Names}}' 2>/dev/null || true)}
SUPPORT_ENV="$ROOT_DIR/gogotex-support-services/.env"
if [ -f "$SUPPORT_ENV" ]; then
  set -o allexport; source "$SUPPORT_ENV"; set +o allexport
fi
MONGO_C=${MONGO_C:-mongodb-mongodb}

# expects: ok/fail helpers and MONGO_C variable

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
