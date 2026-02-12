# MongoDB checks (sourced by scripts/health-check.sh)
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
