# Keycloak checks (sourced by scripts/health-check.sh)
# Standalone bootstrap: define helpers, load .env and defaults so this file
# can be executed directly (e.g. ./scripts/health-check/keycloak.sh).
if ! declare -f ok >/dev/null 2>&1; then
  ok(){ echo "✅ $1"; PASSED=${PASSED:-0}; PASSED=$((PASSED+1)); }
fi
if ! declare -f fail >/dev/null 2>&1; then
  fail(){ echo "❌ $1"; FAILED=${FAILED:-0}; FAILED=$((FAILED+1)); }
fi
ROOT_DIR=${ROOT_DIR:-"$(cd "$(dirname "$0")/.." && pwd)"}
CONTAINERS=${CONTAINERS:-$(docker ps --format '{{.Names}}' 2>/dev/null || true)}
SUPPORT_ENV="$ROOT_DIR/gogotex-support-services/.env"
if [ -f "$SUPPORT_ENV" ]; then
  set -o allexport; source "$SUPPORT_ENV"; set +o allexport
fi
KEYCLOAK_USER=${KEYCLOAK_USER:-admin}
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-changeme_keycloak}

# expects: OK/FAIL helper functions, KEYCLOAK_* vars from caller

KEYCLOAK_C="keycloak-keycloak"

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
