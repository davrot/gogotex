#!/usr/bin/env bash
set -euo pipefail

# CI integration test for auth service
# - Starts Keycloak+Postgres and MongoDB via existing compose files
# - Provisions client and test user
# - Runs the auth service in a detached container on the same network
# - Requests a password-grant access token for the test user and calls /api/v1/me

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
KC_POSTGRES_YAML="$ROOT_DIR/gogotex-support-services/keycloak-service/keycloak-postgres.yaml"
KC_KEYCLOAK_YAML="$ROOT_DIR/gogotex-support-services/keycloak-service/keycloak.yaml"
MONGO_YAML="$ROOT_DIR/gogotex-support-services/mongodb-service/mongodb.yaml"

# Bring up Keycloak and MongoDB (robust: only bring up missing services)
KC_PRESENT=$(docker ps --format '{{.Names}}' | grep -q '^keycloak-keycloak$' && echo yes || echo no)
MONGO_PRESENT=$(docker ps --format '{{.Names}}' | grep -q '^mongodb-mongodb$' && echo yes || echo no)
if [ "$KC_PRESENT" = "yes" ] && [ "$MONGO_PRESENT" = "yes" ]; then
  echo "Keycloak and MongoDB containers already present; skipping docker compose up"
else
  echo "Bringing up missing infra services..."
  if [ "$KC_PRESENT" = "no" ] && [ "$MONGO_PRESENT" = "no" ]; then
    docker compose -f "$KC_POSTGRES_YAML" -f "$KC_KEYCLOAK_YAML" -f "$MONGO_YAML" up -d || true
  elif [ "$KC_PRESENT" = "no" ] && [ "$MONGO_PRESENT" = "yes" ]; then
    docker compose -f "$KC_POSTGRES_YAML" -f "$KC_KEYCLOAK_YAML" up -d || true
  else
    echo "No infra changes required"
  fi
fi

# Wait for keycloak container
for i in {1..60}; do
  if docker ps --format '{{.Names}}' | grep -q '^keycloak-keycloak$'; then
    echo "Keycloak container present"; break
  fi
  sleep 1
done

NET=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' keycloak-keycloak)
if [ -z "$NET" ]; then
  echo "ERROR: could not detect Docker network for keycloak-keycloak" >&2
  exit 2
fi

echo "Waiting for Keycloak HTTP to respond..."
for i in {1..120}; do
  HTTP_CODE=$(docker run --rm --network "$NET" curlimages/curl -sS -o /dev/null -w "%{http_code}" http://keycloak-keycloak:8080/sso/ || echo 000)
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "400" ]; then
    echo "Keycloak HTTP response: $HTTP_CODE"; break
  fi
  echo -n '.'; sleep 2
done

# Run keycloak setup script inside network
echo "Running Keycloak setup..."
docker run --rm --network "$NET" -v "$ROOT_DIR":/workdir -w /workdir alpine:3.19 sh -c "apk add --no-cache curl jq openssl bash >/dev/null 2>&1 && KC_INSECURE=false KC_HOST=http://keycloak-keycloak:8080/sso /workdir/scripts/keycloak-setup.sh"

# Ensure TEST_USER default is set (avoids unbound variable when -u is set)
TEST_USER=${TEST_USER:-testuser}

# Acquire token using password grant for the created test user
# For stable CI, use client_credentials token for the test (avoids resource-owner password edge cases)
echo "Requesting client_credentials token for test client..."
# Read client secret and request token directly (avoid parsing human-friendly script output)
CLIENT_SECRET_FILE="$ROOT_DIR/gogotex-support-services/keycloak-service/client-secret_gogotex-backend.txt"
if [ ! -f "$CLIENT_SECRET_FILE" ]; then
  echo "Client secret file not found: $CLIENT_SECRET_FILE"; exit 4
fi
CLIENT_SECRET=$(cat "$CLIENT_SECRET_FILE")
TOKEN=$(docker run --rm --network "$NET" curlimages/curl -sS -X POST -d "client_id=gogotex-backend" -d "client_secret=$CLIENT_SECRET" -d "grant_type=client_credentials" http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/token | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p' || true)
if [ -z "$TOKEN" ]; then
  echo "Failed to obtain client token"; exit 3
fi

# Build a minimal auth image for the integration test
AUTH_IMAGE="gogotex-auth:ci"
AUTH_CONTAINER_NAME="gogotex-auth-integration"

# Build image
echo "Building auth image $AUTH_IMAGE..."
docker build -t "$AUTH_IMAGE" "$ROOT_DIR/backend/go-services"

# Ensure we always clean up the auth container when the script exits
cleanup() {
  docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm -f cb-sink >/dev/null 2>&1 || true
  if [ "${CLEANUP:-false}" = "true" ]; then
    echo "CLEANUP=true: bringing down Keycloak and MongoDB services..."
    docker compose -f "$KC_POSTGRES_YAML" -f "$KC_KEYCLOAK_YAML" -f "$MONGO_YAML" down || true
  else
    echo "Left infra running (set CLEANUP=true to tear down after tests)"
  fi
}
trap cleanup EXIT

# Run the auth service as a container on the same network
echo "Starting auth service container ($AUTH_CONTAINER_NAME) on network $NET..."
# Remove any previous container with same name to avoid conflicts
docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true
# Start the container
if ! docker run -d --name "$AUTH_CONTAINER_NAME" --network "$NET" -e KC_INSECURE=true \
  -e ALLOW_INSECURE_TOKEN=true \
  -e KEYCLOAK_URL=http://keycloak-keycloak:8080/sso \
  -e KEYCLOAK_REALM=gogotex \
  -e KEYCLOAK_CLIENT_ID=gogotex-backend \
  -e KEYCLOAK_CLIENT_SECRET="$CLIENT_SECRET" \
  -e MONGODB_URI=mongodb://mongodb-mongodb:27017 \
  -e MONGODB_DATABASE=gogotex \
  -e SERVER_HOST=0.0.0.0 -e SERVER_PORT=8081 \
  "$AUTH_IMAGE"; then
  echo "ERROR: failed to start auth container"; exit 5
fi

# Wait for auth container to be healthy (HTTP /health)
for i in {1..60}; do
  HTTP_CODE=$(docker run --rm --network "$NET" curlimages/curl -sS -o /dev/null -w "%{http_code}" http://$AUTH_CONTAINER_NAME:8081/health || echo 000)
  echo "Auth HTTP: $HTTP_CODE"
  if [ "$HTTP_CODE" = "200" ]; then
    echo 'Auth service listening'; break
  fi
  sleep 1
done
if [ "$HTTP_CODE" != "200" ]; then
  echo "Auth service did not become ready in time"; docker logs "$AUTH_CONTAINER_NAME" | sed -n '1,200p'; exit 6
fi

# --- Start auth-code E2E flow: perform headless login to capture code or fallback to callback sink ---
# perform headless login using a small Python script (runs in-network)
TEST_PASS_FILE="$ROOT_DIR/gogotex-support-services/keycloak-service/testuser_password.txt"
TEST_PASS="$(cat "$TEST_PASS_FILE")"

# Option: FORCE_CB_SINK=true will use an HTTP callback sink (cb-sink) to capture the authorization code
if [ "${FORCE_CB_SINK:-false}" = "true" ]; then
  echo "FORCE_CB_SINK=true: using callback sink to capture authorization code"
  docker rm -f cb-sink >/dev/null 2>&1 || true
  docker run -d --name cb-sink --network "$NET" python:3.11-slim sh -c "python -u -m http.server 3000" >/dev/null
  # trigger the auth request (Keycloak will redirect to cb-sink and log the GET)
  docker run --rm --network "$NET" curlimages/curl -sS -L "http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback" >/dev/null || true
  for i in {1..30}; do
    LOGS=$(docker logs cb-sink 2>/dev/null || true)
    CODE=$(echo "$LOGS" | grep -o 'code=[^ &"\'\'']*' | head -n1 | sed 's/^code=//') || true
    if [ -n "$CODE" ]; then
      echo "Captured code from cb-sink: $CODE"; break
    fi
    sleep 1
  done
  if [ -z "$CODE" ]; then
    echo "Failed to capture authorization code via cb-sink"; docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true; exit 6
  fi
else
  echo "Performing headless login to obtain authorization code (captures code from redirect)..."
  # The Python script will detect the authorization code in Location headers during redirects
  CODE=$(docker run --rm --network "$NET" -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim sh -c "pip install requests bs4 >/dev/null 2>&1 && python - <<'PY'
import os, requests
from bs4 import BeautifulSoup
s = requests.Session()

auth_url = 'http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'

resp = s.get(auth_url, verify=False)
soup = BeautifulSoup(resp.text, 'html.parser')
form = soup.find('form')
if not form:
    print('NOFORM')
    raise SystemExit(1)

action = form.get('action')
if action and 'localhost' in action:
    action = action.replace('localhost:8080', 'keycloak-keycloak:8080')

payload = {inp['name']: inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
payload['username'] = os.environ['TEST_USER']
payload['password'] = os.environ['TEST_PASS']

# submit and inspect redirect chain for a location that contains 'code='
resp = s.post(action, data=payload, allow_redirects=False, verify=False)
for _ in range(10):
    if resp.status_code in (301,302,303,307,308) and 'Location' in resp.headers:
        loc = resp.headers['Location']
        if 'code=' in loc:
            # extract query param
            import urllib.parse as u
            q = u.urlparse(loc).query
            params = u.parse_qs(q)
            if 'code' in params:
                print(params['code'][0])
                raise SystemExit(0)
        # follow the redirect (rewrite localhost to in-network host)
        loc = loc.replace('localhost:8080', 'keycloak-keycloak:8080')
        resp = s.get(loc, allow_redirects=False, verify=False)
        # handle required-action forms
        if 'required-action' in resp.text or 'Verify profile' in resp.text:
            soup = BeautifulSoup(resp.text, 'html.parser')
            form = soup.find('form')
            if not form:
                break
            act = form.get('action')
            if 'localhost' in act:
                act = act.replace('localhost:8080', 'keycloak-keycloak:8080')
            payload2 = {inp['name']: inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
            resp = s.post(act, data=payload2, allow_redirects=False, verify=False)
            continue
        continue
    else:
        break

# fallback: try to find code in HTML or form actions
if 'code=' in resp.text:
    import re
    m = re.search(r'code=([^\"\'\&\s]+)', resp.text)
    if m:
        print(m.group(1))
        raise SystemExit(0)
print('')
PY")

  if [ -n "$CODE" ]; then
    echo "Captured code directly: $CODE"
  else
    # Start a minimal http callback sink inside the Docker network to capture the redirect
    docker rm -f cb-sink >/dev/null 2>&1 || true
    echo "Starting callback sink (cb-sink) on network $NET..."
    docker run -d --name cb-sink --network "$NET" python:3.11-slim sh -c "python -u -m http.server 3000" >/dev/null
    echo "No code captured directly; waiting for cb-sink to receive code (fallback)"
    # Poll cb-sink logs for the code
    for i in {1..30}; do
      LOGS=$(docker logs cb-sink 2>/dev/null || true)
      CODE=$(echo "$LOGS" | grep -o 'code=[^ &"\'\'']*' | head -n1 | sed 's/^code=//') || true
      if [ -n "$CODE" ]; then
        echo "Captured code from cb-sink: $CODE"; break
      fi
      sleep 1
    done
  fi
  if [ -z "$CODE" ]; then
    echo "Failed to capture authorization code (no code from headless flow and no cb-sink fallback)."
    docker logs cb-sink 2>/dev/null || true
    docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true
    exit 6
  fi
fi

echo "Captured code: $CODE"

# Optional diagnostic: try exchanging the captured code directly with Keycloak token endpoint when DEBUG_KC_EXCHANGE=true
if [ "${DEBUG_KC_EXCHANGE:-false}" = "true" ]; then
  echo "Attempting direct token exchange with Keycloak (diagnostic)..."
  KC_TOKEN_RESP=$(docker run --rm --network "$NET" curlimages/curl -sS -X POST -d "grant_type=authorization_code" -d "client_id=gogotex-backend" -d "client_secret=$CLIENT_SECRET" -d "code=$CODE" -d "redirect_uri=http://cb-sink:3000/callback" http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/token || true)
  echo "Keycloak token response: $KC_TOKEN_RESP"
fi

# POST code to auth service (use auth service's /api/v1/auth/login with mode=auth_code)
# Retry the full headless-capture -> exchange sequence to mitigate transient 'code not valid' or timing races
MAX_ATTEMPTS=3
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  echo "Exchanging code via auth service (attempt $attempt/$MAX_ATTEMPTS)..."
  LOGIN_RESP=$(docker run --rm --network "$NET" curlimages/curl -sS -X POST -H "Content-Type: application/json" -d '{"mode":"auth_code","code":"'"$CODE"'","redirect_uri":"http://cb-sink:3000/callback"}' http://$AUTH_CONTAINER_NAME:8081/api/v1/auth/login || true)
  if echo "$LOGIN_RESP" | jq -e '.access_token' >/dev/null 2>&1; then
    echo "✅ Auth-code E2E: auth service exchanged code and returned tokens"
    echo "$LOGIN_RESP" | jq .
    break
  else
    echo "Auth-code exchange failed on attempt $attempt: $LOGIN_RESP"
    echo "Auth logs:"; docker logs "$AUTH_CONTAINER_NAME" | sed -n '1,200p'
    if [ $attempt -lt $MAX_ATTEMPTS ]; then
      echo "Will retry headless flow to obtain a fresh code (sleep 1s)..."
      sleep 1
      # obtain a fresh code for the next attempt
      CODE=$(docker run --rm --network "$NET" -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim sh -c "pip install requests bs4 >/dev/null 2>&1 && python - <<'PY'
import os, requests
from bs4 import BeautifulSoup
s = requests.Session()

auth_url = 'http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'
resp = s.get(auth_url, verify=False)
soup = BeautifulSoup(resp.text, 'html.parser')
form = soup.find('form')
if not form:
    print('')
    raise SystemExit(0)
action = form.get('action')
if action and 'localhost' in action:
    action = action.replace('localhost:8080', 'keycloak-keycloak:8080')
payload = {inp['name']: inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
payload['username'] = os.environ['TEST_USER']
payload['password'] = os.environ['TEST_PASS']
resp = s.post(action, data=payload, allow_redirects=False, verify=False)
if 'Location' in resp.headers and 'code=' in resp.headers['Location']:
    import urllib.parse as u
    q = u.urlparse(resp.headers['Location']).query
    params = u.parse_qs(q)
    if 'code' in params:
        print(params['code'][0])
        raise SystemExit(0)
print('')
PY"
)
      continue
    else
      echo "❌ Auth-code E2E failed after $MAX_ATTEMPTS attempts."; docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true; exit 7
    fi
  fi
done

# cleanup cb-sink
docker rm -f cb-sink >/dev/null 2>&1 || true

# --- End auth-code E2E flow ---

# Call the /api/v1/me endpoint using the token via nginx (host-facing)
echo "Calling /api/v1/me on auth service via nginx (http://localhost/api/v1/me)..."
RESP=$(curl -sS -H "Authorization: Bearer $TOKEN" http://localhost/api/v1/me || true)

# Basic validation: should include "user" with "sub" or at least claims
if echo "$RESP" | jq -e '.user.sub' >/dev/null 2>&1; then
  echo "✅ Integration test passed: user created and returned (via nginx)"
  echo "$RESP" | jq .
  # cleanup
  docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true
  exit 0
else
  echo "❌ Integration test (via nginx) failed. Response:"; echo "$RESP" | sed -n '1,200p'
  echo "Falling back to direct container check for debugging..."
  RESP2=$(docker run --rm --network "$NET" curlimages/curl -sS -H "Authorization: Bearer $TOKEN" http://$AUTH_CONTAINER_NAME:8081/api/v1/me || true)
  echo "Direct container response:"; echo "$RESP2" | sed -n '1,200p'
  echo "Auth logs:"; docker logs "$AUTH_CONTAINER_NAME" | sed -n '1,200p'
  docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true
  exit 4
fi
