# nginx quick check (sourced by scripts/health-check.sh)
# Standalone bootstrap: provide ok/fail helpers and load .env
if ! declare -f ok >/dev/null 2>&1; then
  ok(){ echo "✅ $1"; PASSED=${PASSED:-0}; PASSED=$((PASSED+1)); }
fi
if ! declare -f fail >/dev/null 2>&1; then
  fail(){ echo "❌ $1"; FAILED=${FAILED:-0}; FAILED=$((FAILED+1)); }
fi
ROOT_DIR=${ROOT_DIR:-"$(cd "$(dirname "$0")/../.." && pwd)"}
CONTAINERS=${CONTAINERS:-$(docker ps --format '{{.Names}}' 2>/dev/null || true)}
NGINX_C=${NGINX_C:-nginx-nginx}

# expects: NGNIX_C variable and ok/fail helpers

echo
echo "== nginx quick check =="
if [ -n "$NGINX_C" ]; then
  NCODE=$(curl -sS -o /dev/null -w "%{http_code}" http://localhost/ || true)
  if [ "$NCODE" = "000" ]; then
    fail "nginx not responding on http://localhost/"
  else
    ok "nginx responded (code $NCODE)"
  fi
else
  echo "- Skipping nginx check (container missing)"
fi
