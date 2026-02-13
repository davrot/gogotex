#!/usr/bin/env bash
# Robust Keycloak setup script for GoGoTeX
# Moves the logic from test_tools/keycloak-setup.sh to a clearer, network-aware script.

set -euo pipefail

# Load environment from support .env if present (makes scripts portable and CI friendly)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SUPPORT_ENV="$ROOT_DIR/gogotex-support-services/.env"
if [ -f "$SUPPORT_ENV" ]; then
  # shellcheck disable=SC1091
  set -o allexport
  source "$SUPPORT_ENV"
  set +o allexport
fi

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
# Try common host/paths (localhost and container name) including HTTPS variants.
# Set KC_INSECURE=true to accept self-signed certs (adds curl --insecure)
CANDIDATES+=("https://localhost:443" "https://localhost/sso" "http://localhost:8080" "http://localhost/sso" "http://keycloak:8080" "http://keycloak:8080/sso")

# Preflight checks
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

echo "🔎 Trying to locate Keycloak admin API..."
FOUND_HOST=""
TOKEN=""
for host in "${CANDIDATES[@]}"; do
  [ -z "$host" ] && continue
  echo -n " - testing $host ... "
  # Determine curl TLS options
  CURL_OPTS=()
  if [[ "$host" =~ ^https:// ]] || [ "${KC_INSECURE:-false}" = "true" ]; then
    CURL_OPTS+=(--insecure)
  fi

  # Try a set of token endpoints for this candidate host. This helps handle /sso, /auth, or root mounts.
  TOKEN=""
  for token_path in "/realms/master/protocol/openid-connect/token" "/auth/realms/master/protocol/openid-connect/token"; do
    token_url="$host$token_path"
    echo -n "    trying token endpoint $token_url ... "

    # Use curl to capture HTTP code and body
    HTTP_BODY_FILE=$(mktemp)
    HTTP_CODE=$(curl "${CURL_OPTS[@]}" -sS -X POST \
      -d "client_id=admin-cli" \
      -d "username=${ADMIN_USER}" \
      -d "password=${ADMIN_PASS}" \
      -d "grant_type=password" \
      -w "%{http_code}" -o "$HTTP_BODY_FILE" "$token_url" 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ]; then
      TOKEN=$(cat "$HTTP_BODY_FILE")
      rm -f "$HTTP_BODY_FILE"
      echo "OK"
      break
    else
      # Print short debug info
      BODY_SNIPPET=$(head -c 400 "$HTTP_BODY_FILE" | tr -d '\n')
      rm -f "$HTTP_BODY_FILE"
      echo "HTTP $HTTP_CODE, body: ${BODY_SNIPPET}"
    fi
  done

  if [ -n "$TOKEN" ] && [ "$(echo "$TOKEN" | jq -r '.access_token // empty')" != "" ]; then
    ACCESS_TOKEN=$(echo "$TOKEN" | jq -r '.access_token')
    FOUND_HOST="$host"
    break
  else
    echo "    no token from $host"
  fi
done

if [ -z "$FOUND_HOST" ]; then
  echo "ERROR: Could not connect to Keycloak admin API on any candidate host."
  echo "Tried: ${CANDIDATES[*]}"
  echo "Common causes: Keycloak not exposed to host, wrong admin password, or admin-cli direct grant disabled."
  echo "Tip: Try running the script inside the Docker network (e.g. docker exec -it keycloak-keycloak /bin/sh -c \"/scripts/keycloak-setup.sh\") or set KC_HOST to an internal address (http://keycloak-keycloak:8080) and retry."
  exit 2
fi

KC_HOST="$FOUND_HOST"
export KC_HOST

echo "✅ Found Keycloak at $KC_HOST"

# Short helper to make admin API calls
admin_call() {
  method=$1; shift
  path=$1; shift
  if [ "$#" -ge 1 ]; then
    data=$1
    curl -s -S -X "$method" -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" "$KC_HOST$path" --data "$data"
  else
    curl -s -S -X "$method" -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" "$KC_HOST$path"
  fi
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
  echo "Creating client '$CLIENT_ID' (confidential + direct access grants + standard flow enabled)"
  client_json=$(jq -n --arg cid "$CLIENT_ID" '{clientId: $cid, enabled: true, publicClient: false, directAccessGrantsEnabled: true, serviceAccountsEnabled: true, standardFlowEnabled: true, redirectUris: ["http://localhost:3000/*","http://localhost:5001/*","http://cb-sink:3000/*","http://cb-sink:3000/callback","http://frontend/*","http://frontend/auth/callback"], protocol: "openid-connect"}')
  admin_call POST "/admin/realms/$REALM/clients" "$client_json" >/dev/null
  echo "Client created"
fi

# --- Create a dedicated CI/test client that is allowed to use direct access grants ---
CI_CLIENT_ID="gogotex-ci"
echo "Ensuring CI client '$CI_CLIENT_ID' exists (directAccessGrants enabled)..."
ci_exists=$(admin_call GET "/admin/realms/$REALM/clients?clientId=$CI_CLIENT_ID" | jq '.[0] // empty')
if [ -n "$ci_exists" ] && [ "$ci_exists" != "null" ]; then
  echo "CI client '$CI_CLIENT_ID' already exists"
else
  echo "Creating CI client '$CI_CLIENT_ID' (confidential + directAccessGrantsEnabled=true)"
  ci_json=$(jq -n --arg cid "$CI_CLIENT_ID" '{clientId: $cid, enabled: true, publicClient: false, directAccessGrantsEnabled: true, serviceAccountsEnabled: false, standardFlowEnabled: false, protocol: "openid-connect"}')
  admin_call POST "/admin/realms/$REALM/clients" "$ci_json" >/dev/null
  echo "CI client created"
fi

# Ensure CI client has a secret and write it to workspace for CI use (idempotent)
CI_INTERNAL_ID=$(admin_call GET "/admin/realms/$REALM/clients?clientId=$CI_CLIENT_ID" | jq -r '.[0].id')
if [ -n "$CI_INTERNAL_ID" ] && [ "$CI_INTERNAL_ID" != "null" ]; then
  echo "Ensuring client secret for '$CI_CLIENT_ID' (id: $CI_INTERNAL_ID)"
  CI_SECRET_RESP=$(admin_call POST "/admin/realms/$REALM/clients/$CI_INTERNAL_ID/client-secret") || true
  CI_CLIENT_SECRET=$(echo "$CI_SECRET_RESP" | jq -r '.value // empty')
  if [ -n "$CI_CLIENT_SECRET" ]; then
    SECRET_FILE_CI="./gogotex-support-services/keycloak-service/client-secret_${CI_CLIENT_ID}.txt"
    echo "$CI_CLIENT_SECRET" > "$SECRET_FILE_CI"
    chmod 644 "$SECRET_FILE_CI" || true
    echo "CI client secret written to $SECRET_FILE_CI"
  else
    echo "CI client secret already present or could not be created (response: $CI_SECRET_RESP)" || true
  fi
else
  echo "Warning: could not determine internal id for $CI_CLIENT_ID" >&2
fi

# Ensure client has a client secret (confidential client)
CLIENT_INTERNAL_ID=$(admin_call GET "/admin/realms/$REALM/clients?clientId=$CLIENT_ID" | jq -r '.[0].id')
if [ -z "$CLIENT_INTERNAL_ID" ] || [ "$CLIENT_INTERNAL_ID" = "null" ]; then
  echo "ERROR: Cannot find internal client id for $CLIENT_ID" >&2
else
  echo "Ensuring client configuration for '$CLIENT_ID' (id: $CLIENT_INTERNAL_ID)"
  # Ensure direct access grants enabled (allows resource-owner-password credentials)
  CLIENT_REPR=$(admin_call GET "/admin/realms/$REALM/clients/$CLIENT_INTERNAL_ID")
  # Ensure required flags and redirect URIs are present (idempotent)
  UPDATED_CLIENT_REPR=$(echo "$CLIENT_REPR" | jq '.directAccessGrantsEnabled = true | .publicClient = false | .serviceAccountsEnabled = true | .standardFlowEnabled = true | .redirectUris += ["http://cb-sink:3000/*","http://cb-sink:3000/callback","http://frontend/*","http://frontend/auth/callback"] | .redirectUris |= (unique)')
  admin_call PUT "/admin/realms/$REALM/clients/$CLIENT_INTERNAL_ID" "$UPDATED_CLIENT_REPR" >/dev/null || true
  echo "Client configuration updated (directAccessGrantsEnabled = true, standardFlowEnabled = true, redirectUris ensured)"

  echo "Ensuring client secret for '$CLIENT_ID' (id: $CLIENT_INTERNAL_ID)"
  SECRET_RESP=$(admin_call POST "/admin/realms/$REALM/clients/$CLIENT_INTERNAL_ID/client-secret")
  CLIENT_SECRET=$(echo "$SECRET_RESP" | jq -r '.value // empty')
  if [ -n "$CLIENT_SECRET" ]; then
    echo "Client secret obtained for $CLIENT_ID"
    # Save secret to file for developer convenience (workspace safe location)
    SECRET_FILE="./gogotex-support-services/keycloak-service/client-secret_${CLIENT_ID}.txt"
    mkdir -p "$(dirname "$SECRET_FILE")"
    echo "$CLIENT_SECRET" > "$SECRET_FILE"
    chmod 644 "$SECRET_FILE" || true
    echo "Client secret written to $SECRET_FILE"
  else
    echo "Warning: could not obtain a client secret for $CLIENT_ID. Response: $SECRET_RESP" >&2
  fi
fi

# Create or ensure test user and set password (always reset for reproducible tests)
echo "Ensuring test user '$TEST_USER' exists..."
users=$(admin_call GET "/admin/realms/$REALM/users?username=$TEST_USER")
if echo "$users" | jq -e '. | length > 0' >/dev/null 2>&1; then
  echo "Test user exists"
  USER_ID=$(echo "$users" | jq -r '.[0].id')
else
  echo "Creating test user '$TEST_USER'"
  user_json=$(jq -n --arg username "$TEST_USER" --arg email "$TEST_USER_EMAIL" '{username: $username, email: $email, enabled: true}')
  admin_call POST "/admin/realms/$REALM/users" "$user_json" >/dev/null
  USER_ID=$(admin_call GET "/admin/realms/$REALM/users?username=$TEST_USER" | jq -r '.[0].id')
  echo "Test user created (id: $USER_ID)"
fi

# Decide on password: env or generated
if [ -z "${TEST_USER_PASSWORD:-}" ]; then
  TEST_USER_PASSWORD=$(openssl rand -base64 12 || echo "Test123!")
  echo "Generated password for $TEST_USER: $TEST_USER_PASSWORD"
else
  echo "Using provided TEST_USER_PASSWORD for $TEST_USER"
fi

# Set/reset the user's password
cred_json=$(jq -n --arg val "$TEST_USER_PASSWORD" '{type: "password", temporary: false, value: $val}')
admin_call PUT "/admin/realms/$REALM/users/$USER_ID/reset-password" "$cred_json" >/dev/null
echo "Test user password set/reset"

# Ensure user is fully configured: mark emailVerified true and clear required actions
update_json=$(jq -n --argjson enabled true --arg emailVerified true '{enabled: $enabled, emailVerified: $emailVerified, requiredActions: []}')
admin_call PUT "/admin/realms/$REALM/users/$USER_ID" "$update_json" >/dev/null
echo "Test user marked as emailVerified and required actions cleared"

# Save password to a file for automation (dev convenience)
USER_PASS_FILE="./gogotex-support-services/keycloak-service/testuser_password.txt"
mkdir -p "$(dirname "$USER_PASS_FILE")"
echo "$TEST_USER_PASSWORD" > "$USER_PASS_FILE"
chmod 644 "$USER_PASS_FILE" || true
echo "Test user password written to $USER_PASS_FILE"

# Quick verification: attempt to exchange user credentials for token using the created client
if [ -n "${CLIENT_SECRET:-}" ]; then
  echo "Verifying test user can obtain a token using client id '$CLIENT_ID'..."
  TOKEN_TEST_RESP=$(curl ${KC_INSECURE:+--insecure} -sS -X POST -d "client_id=$CLIENT_ID" -d "client_secret=$CLIENT_SECRET" -d "username=$TEST_USER" -d "password=$TEST_USER_PASSWORD" -d "grant_type=password" "$KC_HOST/realms/$REALM/protocol/openid-connect/token" 2>/dev/null || true)
  if [ -n "$TOKEN_TEST_RESP" ] && [ "$(echo "$TOKEN_TEST_RESP" | jq -r '.access_token // empty' 2>/dev/null)" != "" ]; then
    echo "✅ Test user login succeeded (access token received)"
    # Print short token info
    echo "Access token (short): $(echo "$TOKEN_TEST_RESP" | jq -r '.access_token' | cut -c1-60)..."
  else
    echo "⚠️ Test user login failed using client secret. Response:"
    echo "$TOKEN_TEST_RESP" | sed -n '1,20p'
    echo "You may need to enable direct access grants for the client or use a different client configuration."
  fi
else
  echo "Skipped test user login verification: no client secret available for $CLIENT_ID"
fi

echo "✅ Keycloak setup finished (realm: $REALM, test user: $TEST_USER)"
exit 0
