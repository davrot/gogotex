# Redis checks (sourced by scripts/health-check.sh)
# expects: ok/fail helpers, REDIS_C and REDIS_PASSWORD variables, CONTAINERS list

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
