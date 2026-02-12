# Keycloak checks (sourced by scripts/health-check.sh)
# expects: OK/FAIL helper functions, KEYCLOAK_* vars from caller

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
