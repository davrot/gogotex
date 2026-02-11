#!/usr/bin/env bash
# Robust Keycloak setup script for GoGoTeX
# Moves the logic from test_tools/keycloak-setup.sh to a clearer, network-aware script.

set -euo pipefail

ADMIN_USER=${KEYCLOAK_ADMIN:-admin}
ADMIN_PASS=${KEYCLOAK_ADMIN_PASSWORD:-changeme_keycloak}
REALM=${KEYCLOAK_REALM:-gogotex}
CLIENT_ID=${KEYCLOAK_CLIENT_ID:-gogotex-backend}
TEST_USER=${TEST_USER:-testuser}
TEST_USER_EMAIL=${TEST_USER_EMAIL:-testuser@gogotex.local}
TEST_USER_PASSWORD=${TEST_USER_PASSWORD:-}

# Candidates for Keycloak base URL (tries these until one works).
CANDIDATES=()
if [ -n "${KC_HOST:-}" ]; then
  CANDIDATES+=("${KC_HOST}")
fi
CANDIDATES+=("http://localhost/sso" )

# Preflight checks
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

echo "🔎 Trying to locate Keycloak admin API..."
FOUND_HOST=""
TOKEN=""
for host in "${CANDIDATES[@]}"; do
  [ -z "$host" ] && continue
  echo -n " - testing $host ... "
  # Try to request a token (this also implicitly verifies connectivity)
  TOKEN=$(curl -s -S -X POST \
    -d "client_id=admin-cli" \
    -d "username=${ADMIN_USER}" \
    -d "password=${ADMIN_PASS}" \
    -d "grant_type=password" \
    "$host/realms/master/protocol/openid-connect/token" 2>/dev/null || true)

  if [ -n "$TOKEN" ] && [ "$(echo "$TOKEN" | jq -r .access_token // empty)" != "" ]; then
    ACCESS_TOKEN=$(echo "$TOKEN" | jq -r .access_token)
    FOUND_HOST="$host"
    echo "OK"
    break
  else
    echo "no token"
  fi
done

if [ -z "$FOUND_HOST" ]; then
  echo "ERROR: Could not connect to Keycloak admin API on any candidate host."
  echo "Tried: ${CANDIDATES[*]}"
  exit 2
fi

KC_HOST="$FOUND_HOST"
export KC_HOST

echo "✅ Found Keycloak at $KC_HOST"

# Short helper to make admin API calls
admin_call() {
  method=$1; shift
  path=$1; shift
  data=$1 || true
  curl -s -S -X "$method" -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" "$KC_HOST$path" ${data:+--data "$data"}
}

# Create realm if missing
echo "Checking realm '$REALM'..."
if admin_call GET "/admin/realms/$REALM" | jq -e '.realm' >/dev/null 2>&1; then
  echo "Realm '$REALM' already exists"
else
  echo "Creating realm '$REALM'"
  realm_json=$(jq -n --arg realm "$REALM" '{realm: $realm, enabled: true}')
  admin_call POST "/admin/realms" "$realm_json" >/dev/null
  echo "Realm created"
fi

# Create client if missing
echo "Ensuring client '$CLIENT_ID' exists..."
client_exists=$(admin_call GET "/admin/realms/$REALM/clients?clientId=$CLIENT_ID" | jq '.[0] // empty')
if [ -n "$client_exists" ] && [ "$client_exists" != "null" ]; then
  echo "Client '$CLIENT_ID' already exists"
else
  echo "Creating client '$CLIENT_ID'"
  client_json=$(jq -n --arg cid "$CLIENT_ID" --argjson bool true '{clientId: $cid, enabled: true, publicClient: false, redirectUris: ["http://localhost:3000/*","http://localhost:5001/*"], protocol: "openid-connect"}')
  admin_call POST "/admin/realms/$REALM/clients" "$client_json" >/dev/null
  echo "Client created"
fi

# Create test user if missing
echo "Ensuring test user '$TEST_USER' exists..."
users=$(admin_call GET "/admin/realms/$REALM/users?username=$TEST_USER")
if echo "$users" | jq -e '. | length > 0' >/dev/null 2>&1; then
  echo "Test user exists"
else
  echo "Creating test user '$TEST_USER'"
  user_json=$(jq -n --arg username "$TEST_USER" --arg email "$TEST_USER_EMAIL" '{username: $username, email: $email, enabled: true}')
  admin_call POST "/admin/realms/$REALM/users" "$user_json" >/dev/null
  USER_ID=$(admin_call GET "/admin/realms/$REALM/users?username=$TEST_USER" | jq -r '.[0].id')

  if [ -z "$TEST_USER_PASSWORD" ]; then
    # Generate a reasonably strong password if not provided
    TEST_USER_PASSWORD=$(openssl rand -base64 12 || echo "Test123!")
    echo "Generated password for $TEST_USER: $TEST_USER_PASSWORD"
  fi

  cred_json=$(jq -n --arg val "$TEST_USER_PASSWORD" '{type: "password", temporary: false, value: $val}')
  admin_call PUT "/admin/realms/$REALM/users/$USER_ID/reset-password" "$cred_json" >/dev/null
  echo "Test user created with configured password"
fi

echo "✅ Keycloak setup finished (realm: $REALM, test user: $TEST_USER)"
exit 0
