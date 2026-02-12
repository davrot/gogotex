# nginx quick check (sourced by scripts/health-check.sh)
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
