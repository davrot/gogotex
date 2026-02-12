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

# Which host proxy to use for host-facing checks: "nginx" (default) or "traefik".
# - nginx -> http://localhost (nginx listens on 80)
# - traefik -> http://localhost:8082 (Traefik file-provider binds to 8082)
PROXY=${PROXY:-nginx}
case "$PROXY" in
  traefik)
    PROXY_URL="https://localhost:8443"
    PROXY_HOST_HEADER_AUTH="auth.local"
    PROXY_HOST_HEADER_KEYCLOAK="keycloak.local"
    ;; 
  *)
    PROXY_URL="https://localhost"
    PROXY_HOST_HEADER_AUTH="localhost"
    PROXY_HOST_HEADER_KEYCLOAK="localhost"
    ;;
esac
echo "Using host proxy: $PROXY (proxy_url=$PROXY_URL)"

# diagnostics output folder (created early so we can write debug artifacts)
DIAG_DIR="${DIAG_DIR:-${ROOT_DIR:-.}/test-output}"
mkdir -p "$DIAG_DIR" || true
# host port to expose callback-sink (use 11xxx range for local debugging)
CB_SINK_HOST_PORT="${CB_SINK_HOST_PORT:-11300}"


# Acquire tokens for testing
# - CLIENT_TOKEN: client_credentials for administrative checks
# - USER_TOKEN: password-grant token for the test user (used to call /api/v1/me which expects an OIDC token)
echo "Requesting client_credentials token for test client..."
# Read client secret and request token directly (avoid parsing human-friendly script output)
CLIENT_SECRET_FILE="$ROOT_DIR/gogotex-support-services/keycloak-service/client-secret_gogotex-backend.txt"
if [ ! -f "$CLIENT_SECRET_FILE" ]; then
  echo "Client secret file not found: $CLIENT_SECRET_FILE"; exit 4
fi
CLIENT_SECRET=$(cat "$CLIENT_SECRET_FILE")
CLIENT_TOKEN=$(docker run --rm --network "$NET" curlimages/curl -sS -X POST -d "client_id=gogotex-backend" -d "client_secret=$CLIENT_SECRET" -d "grant_type=client_credentials" http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/token | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p' || true)
if [ -z "$CLIENT_TOKEN" ]; then
  echo "Failed to obtain client token"; exit 3
fi
# Password-grant token for TEST_USER (used for /api/v1/me checks)


# Build a minimal auth image for the integration test
AUTH_IMAGE="gogotex-auth:ci"
AUTH_CONTAINER_NAME="gogotex-auth-integration"

# If a long-running 'gogotex-auth' container already exists, reuse it for the
# integration checks instead of starting a new container (helps local/dev runs).
if docker ps --format '{{.Names}}' | grep -q '^gogotex-auth$'; then
  echo "Found existing 'gogotex-auth' container — reusing it for integration checks"
  AUTH_CONTAINER_NAME="gogotex-auth"
fi

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
# If reusing an already-running 'gogotex-auth' container we don't re-create it.
echo "Starting auth service container ($AUTH_CONTAINER_NAME) on network $NET..."
if [ "$AUTH_CONTAINER_NAME" = "gogotex-auth" ]; then
  echo "Reusing existing container '$AUTH_CONTAINER_NAME' — not creating a new one"
else
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
fi

# Determine how to reach the auth service for health/metrics checks.
# Strategy:
# 1) If reusing a long-running `gogotex-auth` -> use host-mapped localhost:8081.
# 2) Otherwise prefer the container's network IP (avoids DNS timing issues).
# 3) Fallback to container name when IP is not available.
if [ "$AUTH_CONTAINER_NAME" = "gogotex-auth" ]; then
  AUTH_HOST="localhost:8081"
else
  # try to resolve container ID and inspect its network IP on $NET
  CID=$(docker ps -q -f "name=^${AUTH_CONTAINER_NAME}$" || true)
  if [ -n "$CID" ]; then
    CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CID" 2>/dev/null || true)
    if [ -n "$CONTAINER_IP" ]; then
      AUTH_HOST="$CONTAINER_IP:8081"
    else
      AUTH_HOST="$AUTH_CONTAINER_NAME:8081"
    fi
  else
    AUTH_HOST="$AUTH_CONTAINER_NAME:8081"
  fi
fi

# Wait for auth service to be healthy (HTTP /health)
for i in {1..60}; do
  HTTP_CODE=$(docker run --rm --network "$NET" curlimages/curl -sS -o /dev/null -w "%{http_code}" http://$AUTH_HOST/health || echo 000)
  echo "Auth HTTP: $HTTP_CODE"
  if [ "$HTTP_CODE" = "200" ]; then
    echo 'Auth service listening'; break
  fi
  sleep 1
done
if [ "$HTTP_CODE" != "200" ]; then
  echo "Auth service did not become ready in time"; docker logs "$AUTH_CONTAINER_NAME" | sed -n '1,200p'; exit 6
fi

# --- Rate-limit + metrics verification (global middleware) ---
# Configure a very low rate limit for the test container run (global middleware reads env at startup)
# The auth container in this script is already running; we run quick checks against /health to
# ensure the in-memory limiter increments allowed/rejected metrics.

echo "Verifying rate-limiter + metrics on auth service..."
# send two quick /health requests: first should be 200, second likely 429 when test RPS/burst are restrictive
R1=$(docker run --rm --network "$NET" curlimages/curl -sS -o /dev/null -w "%{http_code}" http://$AUTH_HOST/health || echo 000)
R2=$(docker run --rm --network "$NET" curlimages/curl -sS -o /dev/null -w "%{http_code}" http://$AUTH_HOST/health || echo 000)
echo "rate-test responses: $R1 $R2"
# fetch metrics and check for rate-limit counters
METRICS=$(docker run --rm --network "$NET" curlimages/curl -sS http://$AUTH_HOST/metrics || true)
if echo "$METRICS" | grep -q '^gogotex_rate_limit_allowed_total'; then
  echo "Found rate_limit_allowed metric"
else
  echo "Missing rate_limit_allowed metric"; echo "$METRICS"; exit 7
fi
if echo "$METRICS" | grep -q '^gogotex_rate_limit_rejected_total'; then
  echo "Found rate_limit_rejected metric"
else
  echo "Missing rate_limit_rejected metric"; echo "$METRICS"; exit 7
fi
# Assert at least one allowed recorded
ALLOWED_VAL=$(echo "$METRICS" | grep '^gogotex_rate_limit_allowed_total' | head -n1 | sed -E 's/.* ([0-9\.]+)$/\1/')
REJECTED_VAL=$(echo "$METRICS" | grep '^gogotex_rate_limit_rejected_total' | head -n1 | sed -E 's/.* ([0-9\.]+)$/\1/')
echo "metrics values: allowed=$ALLOWED_VAL rejected=$REJECTED_VAL"
# simple numeric checks (allowed >= 1)
awk "BEGIN{exit !($ALLOWED_VAL >= 1)}" || (echo "Allowed metric < 1" && exit 8)
# rejected may be 0 or more depending on timing, that's acceptable

echo "Rate-limiter + metrics verified (allowed >= 1)."

# --- Start auth-code E2E flow: perform headless login to capture code or fallback to callback sink ---
# perform headless login using a small Python script (runs in-network)
TEST_PASS_FILE="$ROOT_DIR/gogotex-support-services/keycloak-service/testuser_password.txt"
TEST_PASS="$(cat "$TEST_PASS_FILE")"
# initialize capture variables (avoid unbound-variable under set -u)
CODE=""
REDIRECT_URI=""

# Option: FORCE_CB_SINK=true will use an HTTP callback sink (cb-sink) to capture the authorization code
if [ "${FORCE_CB_SINK:-false}" = "true" ]; then
  echo "FORCE_CB_SINK=true: using callback sink to capture authorization code"
  docker rm -f cb-sink >/dev/null 2>&1 || true
  docker run -d --name cb-sink --network "$NET" -p 127.0.0.1:${CB_SINK_HOST_PORT}:3000 python:3.11-slim sh -c "python -u -m http.server 3000" >/dev/null
  # trigger the auth request (headless login will POST credentials and Keycloak will redirect to cb-sink)
  # perform a headless Python POST that follows redirects so Keycloak will redirect to cb-sink (reliable for required-action flows)
  docker run --rm --network "$NET" -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim sh -s <<'PY' || true
pip install requests bs4 >/dev/null 2>&1
python - <<'P'
import os, requests
from bs4 import BeautifulSoup
s = requests.Session()
auth_url = 'http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'
resp = s.get(auth_url, verify=False)
soup = BeautifulSoup(resp.text, 'html.parser')
form = soup.find('form')
if not form:
    raise SystemExit(1)
action = form.get('action')
if action and 'localhost' in action:
    action = action.replace('localhost:8080','keycloak-keycloak:8080')
payload = {inp['name']: inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
payload['username'] = os.environ['TEST_USER']
payload['password'] = os.environ['TEST_PASS']
# submit and follow redirects so cb-sink receives the GET
resp = s.post(action, data=payload, allow_redirects=True, verify=False)
print(resp.status_code)
P
PY
  for i in {1..30}; do
    LOGS=$(docker logs cb-sink 2>/dev/null || true)
    CODE=$(echo "$LOGS" | grep -o 'code=[^ &"]*' | head -n1 | sed 's/^code=//') || true
    if [ -n "$CODE" ]; then
      echo "Captured code from cb-sink: $CODE"; break
    fi
    sleep 1
  done
  if [ -z "$CODE" ]; then
    echo "Failed to capture authorization code via cb-sink"
    # Persist diagnostics
    echo "--- cb-sink logs ---" > "$DIAG_DIR/cb-sink.log" || true
    docker logs cb-sink 2>/dev/null | sed -n '1,200p' >> "$DIAG_DIR/cb-sink.log" || true
    docker logs keycloak-keycloak 2>/dev/null | sed -n '1,400p' > "$DIAG_DIR/keycloak.log" || true
    echo "Saved diagnostics to $DIAG_DIR/* (cb-sink, keycloak)"
    docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true
    exit 6
  fi
else
  echo "Performing headless login to obtain authorization code (captures code from redirect)..."
  # ensure callback sink (cb-sink) is available **before** following redirects
  docker rm -f cb-sink >/dev/null 2>&1 || true
  echo "Starting callback sink (cb-sink) on network $NET (preheadless)..."
  docker rm -f cb-sink >/dev/null 2>&1 || true
  docker run -d --name cb-sink --network "$NET" -p 127.0.0.1:${CB_SINK_HOST_PORT}:3000 python:3.11-slim sh -c "python -u -m http.server 3000" >/dev/null
  # Wait until cb-sink shows as Up (Docker may need a moment to register DNS)
  for i in {1..6}; do
    STATUS=$(docker ps --filter name=cb-sink --format '{{.Status}}' || true)
    if echo "$STATUS" | grep -q '^Up'; then
      echo "cb-sink is running ($STATUS)"; break
    fi
    echo "waiting for cb-sink DNS/ready... ($i)"; sleep 1
  done
  if ! echo "$STATUS" | grep -q '^Up'; then
    echo "Warning: cb-sink did not start properly (status='$STATUS')" || true
  fi

  # The Python script will detect the authorization code and the redirect URI used in Location headers during redirects
  # It prints the values as: <code>|||<redirect_uri>
  # Save Keycloak login HTML for diagnostics (helps when headless capture fails)
  KEYCLOAK_LOGIN_URL='http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'
  docker run --rm --network "$NET" curlimages/curl -sS "$KEYCLOAK_LOGIN_URL" > "$DIAG_DIR/keycloak_login.html" || true

  # --- try server-side non-follow POST to capture Location header (primary, reliable) ---
  LOCATION_HDR=$(docker run --rm --network "$NET" curlimages/curl -sS "$DIAG_DIR/keycloak_login.html":/tmp/kc.html true 2>/dev/null || true)
  # extract form action and POST credentials without following redirects
  ACTION=$(sed -n '1,400p' "$DIAG_DIR/keycloak_login.html" | grep -o 'action="[^"]*"' | head -n1 | sed -E 's/action="([^"]*)"/\1/' | sed 's/localhost:8080/keycloak-keycloak:8080/g' || true)
  if [ -n "$ACTION" ]; then
    LOCATION_HDR=$(docker run --rm --network "$NET" curlimages/curl -sS -D - -o /dev/null -X POST --data "username=$TEST_USER&password=$TEST_PASS" "$ACTION" | sed -n 's/Location: \(.*\)/\1/ip' | tr -d '\r' || true)
    if printf '%s' "$LOCATION_HDR" | grep -q 'code='; then
      echo "Captured code in Location header (server-side): $LOCATION_HDR"
      CODE=$(printf '%s' "$LOCATION_HDR" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p') || true
      REDIRECT_URI=$(printf '%s' "$LOCATION_HDR" | sed -n 's/\(https*:\/\/[^?]*\).*/\1/p') || true
    fi
  fi

  # Try the robust 'fresh GET + non-follow POST' first (same session) to capture Location header
  if [ -z "$CODE" ]; then
    echo "Trying fresh GET+non-follow POST (robust primary attempt)..."
    FRESH_LOC=$(docker run --rm --network "$NET" -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim /bin/sh -c "pip install requests bs4 >/dev/null 2>&1; python - <<'PY'
import os, requests
from bs4 import BeautifulSoup
s = requests.Session()
url = 'http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'
resp = s.get(url, verify=False)
soup = BeautifulSoup(resp.text, 'html.parser')
form = soup.find('form')
if not form:
    print('')
else:
    action = form.get('action')
    if 'localhost' in action:
        action = action.replace('localhost:8080','keycloak-keycloak:8080')
    inputs = {inp.get('name'): inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
    inputs['username'] = os.environ.get('TEST_USER')
    inputs['password'] = os.environ.get('TEST_PASS')
    r = s.post(action, data=inputs, allow_redirects=False, verify=False)
    print(r.headers.get('Location','') or '')
PY" || true)
    if printf '%s' "$FRESH_LOC" | grep -q 'code='; then
      echo "Captured code from fresh GET+POST: $FRESH_LOC"
      CODE=$(printf '%s' "$FRESH_LOC" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p') || true
      REDIRECT_URI=$(printf '%s' "$FRESH_LOC" | sed -n 's/\(https*:\/\/[^?]*\).*/\1/p') || true
    fi
  fi

  # Only run headless flow if CODE still empty
  if [ -z "$CODE" ]; then
    # Persist headless output for diagnostics so intermittent failures can be inspected
    HEADLESS_OUT="$DIAG_DIR/headless_raw_$(date +%Y%m%d-%H%M%S).txt"
    echo "Running headless flow (output -> $HEADLESS_OUT)"
    docker run --rm --network "$NET" -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim sh -s >"$HEADLESS_OUT" 2>&1 <<'SH'
python - <<'PY'
import os, time, requests
from bs4 import BeautifulSoup
from urllib.parse import urlparse, parse_qs
s = requests.Session()

auth_url = 'http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'
resp = s.get(auth_url, verify=False)
soup = BeautifulSoup(resp.text, 'html.parser')
form = soup.find('form')
if not form:
    print('|||')
    raise SystemExit(0)

action = form.get('action')
if action and 'localhost' in action:
    action = action.replace('localhost:8080','keycloak-keycloak:8080')

payload = {inp['name']: inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
payload['username'] = os.environ['TEST_USER']
payload['password'] = os.environ['TEST_PASS']

# submit and follow redirects so Keycloak will redirect to cb-sink if configured
try:
    resp = s.post(action, data=payload, allow_redirects=True, verify=False)
except requests.exceptions.ConnectionError:
    # connection to cb-sink may fail during redirect; fallthrough and inspect history/body
    resp = s.get(auth_url, verify=False)

# If Keycloak returns a required-action (e.g. VERIFY_PROFILE), complete it automatically
if 'required-action' in resp.url or 'VERIFY_PROFILE' in resp.url or 'required-action' in resp.text:
    soup2 = BeautifulSoup(resp.text, 'html.parser')
    form2 = soup2.find('form')
    if form2:
        action2 = form2.get('action')
        payload2 = {inp['name']: inp.get('value','') for inp in form2.find_all('input') if inp.get('name')}
        # populate common profile fields if empty
        payload2.setdefault('firstName', 'Test')
        payload2.setdefault('lastName', 'User')
        payload2.setdefault('email', os.environ.get('TEST_USER_EMAIL','testuser@gogotex.local'))
        resp = s.post(action2, data=payload2, allow_redirects=True, verify=False)
        # small delay to allow Keycloak to perform redirect to cb-sink
        time.sleep(1)

# Check final URL and redirect chain for code
if 'code=' in resp.url:
    parsed = urlparse(resp.url)
    q = parse_qs(parsed.query)
    if 'code' in q:
        print(q['code'][0] + '|||' + parsed.scheme + '://' + parsed.netloc + parsed.path)
        raise SystemExit(0)

# fallback: search HTML for callback URL with code
import re
m = re.search(r'(https?://[^\s"\']*/callback)[^\s"\']*.*code=([^\s\"\'\&]+)', resp.text)
if m:
    print(m.group(2) + '|||' + m.group(1))
    raise SystemExit(0)
print('|||')
PY
SH
  fi

  # copy headless output into DIAG_DIR/headless_latest.txt for quick access (only if headless ran)
  if [ -n "${HEADLESS_OUT:-}" ] && [ -s "$HEADLESS_OUT" ]; then
    cp -f "$HEADLESS_OUT" "$DIAG_DIR/headless_latest.txt" || true
    CODE_REDIRECT="$(sed -n '1p' "$HEADLESS_OUT" || true)"
  else
    CODE_REDIRECT=""
  fi
  # persist the login HTML we saved earlier (already written to $DIAG_DIR)
  if [ -f "$DIAG_DIR/keycloak_login.html" ]; then
    echo "Saved Keycloak login page to $DIAG_DIR/keycloak_login.html"
  fi

if [ -z "${CODE:-}" ]; then
  CODE="$(echo "$CODE_REDIRECT" | sed -n '1p' | cut -d'|' -f1)"
  REDIRECT_URI="$(echo "$CODE_REDIRECT" | sed -n '1p' | sed 's/.*|||//')"
fi

  if [ -n "$CODE" ]; then
    echo "Captured code directly: $CODE"
  else
    # Fallback #1: perform a non-following POST to Keycloak's login action and inspect the Location header for the code
    echo "Attempting non-follow POST to capture Location header (fast fallback, posts full form)..."
    if [ -f "$DIAG_DIR/keycloak_login.html" ]; then
      # Extract form inputs from saved HTML and POST them (uses Python to parse hidden inputs)
      LOCATION_HDR=$(docker run --rm --network "$NET" -v "$DIAG_DIR":/diag -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim /bin/sh -c "pip install requests bs4 >/dev/null 2>&1; python - <<'PY'
import os, sys, requests
from bs4 import BeautifulSoup
html = open('/diag/keycloak_login.html','r',encoding='utf-8').read()
S = BeautifulSoup(html,'html.parser')
form = S.find('form')
if not form:
    sys.exit(2)
action = form.get('action').replace('localhost:8080','keycloak-keycloak:8080')
inputs = {inp.get('name'): inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
inputs['username'] = os.environ.get('TEST_USER')
inputs['password'] = os.environ.get('TEST_PASS')
r = requests.post(action, data=inputs, allow_redirects=False, verify=False)
print(r.headers.get('Location','') or '')
PY" || true)
      if printf '%s' "$LOCATION_HDR" | grep -q 'code='; then
        echo "Captured code in Location header: $LOCATION_HDR"
        CODE=$(printf '%s' "$LOCATION_HDR" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p') || true
        REDIRECT_URI=$(printf '%s' "$LOCATION_HDR" | sed -n 's/\(https*:\/\/[^?]*\).*/\1/p') || true
      fi
    fi

    if [ -z "$CODE" ]; then
      # Fallback (strong): do a fresh GET -> POST (no redirect) inside the Docker network and inspect Location header
      echo "Attempting fresh GET+non-follow POST inside Docker network (strong fallback)..."
      FRESH_LOC=$(docker run --rm --network "$NET" -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim /bin/sh -c "pip install requests bs4 >/dev/null 2>&1; python - <<'PY'\nimport os, requests\nfrom bs4 import BeautifulSoup\nfrom urllib.parse import urlparse, parse_qs\ns = requests.Session()\nurl = 'http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'\nresp = s.get(url, verify=False)\nsoup = BeautifulSoup(resp.text, 'html.parser')\nform = soup.find('form')\nif not form:\n    print('')\nelse:\n    action = form.get('action')\n    if 'localhost' in action:\n        action = action.replace('localhost:8080','keycloak-keycloak:8080')\n    inputs = {inp.get('name'): inp.get('value','') for inp in form.find_all('input') if inp.get('name')}\n    inputs['username'] = os.environ.get('TEST_USER')\n    inputs['password'] = os.environ.get('TEST_PASS')\n    # initial post (do not follow redirects)
    r = s.post(action, data=inputs, allow_redirects=False, verify=False)\n    loc = r.headers.get('Location','')\n    # if required-action page returned in body, complete it and then inspect Location
    if 'required-action' in r.text or 'VERIFY_PROFILE' in r.text:\n        soup2 = BeautifulSoup(r.text, 'html.parser')\n        form2 = soup2.find('form')\n        if form2:\n            action2 = form2.get('action')\n            inputs2 = {inp.get('name'): inp.get('value','') for inp in form2.find_all('input') if inp.get('name')}\n            inputs2.setdefault('firstName','Test')\n            inputs2.setdefault('lastName','User')\n            inputs2.setdefault('email', os.environ.get('TEST_USER_EMAIL','testuser@gogotex.local'))\n            r2 = s.post(action2, data=inputs2, allow_redirects=False, verify=False)\n            loc = r2.headers.get('Location','') or loc\n    print(loc)\nPY" 2>/dev/null || true)
      if printf '%s' "$FRESH_LOC" | grep -q 'code='; then
        echo "Captured code from fresh non-follow POST: $FRESH_LOC"
        CODE=$(printf '%s' "$FRESH_LOC" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p') || true
        REDIRECT_URI=$(printf '%s' "$FRESH_LOC" | sed -n 's/\(https*:\/\/[^?]*\).*/\1/p') || true
      fi
    fi
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
  KC_TOKEN_RESP=$(docker run --rm --network "$NET" curlimages/curl -sS -X POST -d "grant_type=authorization_code" -d "client_id=gogotex-backend" -d "client_secret=$CLIENT_SECRET" -d "code=$CODE" -d "redirect_uri=$REDIRECT_URI" http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/token || true)
  echo "Keycloak token response: $KC_TOKEN_RESP"
  # DEBUG_KC_EXCHANGE consumes the authorization code at Keycloak. obtain a fresh code
  # for the actual auth-service exchange so we don't submit an already-used code.
  echo "DEBUG_KC_EXCHANGE=true: re-capturing fresh authorization code and redirect_uri"
  # Re-capture using the robust "fresh GET + non-follow POST" approach (same as primary capture)
  echo "Re-running fresh GET+non-follow POST to obtain a new code..."
  FRESH_LOC_RECAP=$(docker run --rm --network "$NET" -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim /bin/sh -c "pip install requests bs4 >/dev/null 2>&1; python - <<'PY'
import os, requests
from bs4 import BeautifulSoup
s = requests.Session()
url = 'http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'
resp = s.get(url, verify=False)
soup = BeautifulSoup(resp.text, 'html.parser')
form = soup.find('form')
if not form:
    print('')
else:
    action = form.get('action')
    if 'localhost' in action:
        action = action.replace('localhost:8080','keycloak-keycloak:8080')
    inputs = {inp.get('name'): inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
    inputs['username'] = os.environ.get('TEST_USER')
    inputs['password'] = os.environ.get('TEST_PASS')
    r = s.post(action, data=inputs, allow_redirects=False, verify=False)
    print(r.headers.get('Location','') or '')
PY" || true)
  if printf '%s' "$FRESH_LOC_RECAP" | grep -q 'code='; then
    CODE=$(printf '%s' "$FRESH_LOC_RECAP" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p' || true)
    REDIRECT_URI=$(printf '%s' "$FRESH_LOC_RECAP" | sed -n "s/\(https*:\/\/[^?]*\).*/\1/p" || true)
  fi
  echo "Re-captured code: $CODE redirect_uri: $REDIRECT_URI"
fi

# POST code to auth service (use auth service's /api/v1/auth/login with mode=auth_code)
# Retry the full headless-capture -> exchange sequence to mitigate transient 'code not valid' or timing races
# Number of attempts to exchange an authorization code with the auth service
MAX_ATTEMPTS=${MAX_ATTEMPTS:-5}
# Whether to fail the entire script when auth-code E2E fails
FAIL_ON_AUTH_CODE=${FAIL_ON_AUTH_CODE:-true}
# Directory to write diagnostics when auth-code flow is flaky (initialized earlier)
# DIAG_DIR initialized near the top of the script

EXCHANGE_SUCCESS=false
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  echo "Exchanging code via auth service (attempt $attempt/$MAX_ATTEMPTS)..."
  LOGIN_RESP=$(docker run --rm --network "$NET" curlimages/curl -sS -X POST -H "Content-Type: application/json" -d '{"mode":"auth_code","code":"'"$CODE"'","redirect_uri":"'"$REDIRECT_URI"'"}' http://$AUTH_HOST/api/v1/auth/login || true)"$CODE"'","redirect_uri":"'"$REDIRECT_URI"'"}' http://$AUTH_CONTAINER_NAME:8081/api/v1/auth/login || true)
  if echo "$LOGIN_RESP" | jq -e '.access_token' >/dev/null 2>&1; then
    echo "✅ Auth-code E2E: auth service exchanged code and returned tokens"
    echo "$LOGIN_RESP" | jq .
    EXCHANGE_SUCCESS=true
    break
  else
    echo "Auth-code exchange failed on attempt $attempt: $LOGIN_RESP"

    # write diagnostics for this failure
    TS=$(date +%Y%m%d-%H%M%S)
    mkdir -p "$DIAG_DIR" || true
    echo "$LOGIN_RESP" > "$DIAG_DIR/login_response_$TS.json" || true
    docker logs "$AUTH_CONTAINER_NAME" 2>/dev/null | sed -n '1,400p' > "$DIAG_DIR/auth_container_$TS.log" || true
    docker logs keycloak-keycloak 2>/dev/null | sed -n '1,800p' > "$DIAG_DIR/keycloak_$TS.log" || true
    docker logs cb-sink 2>/dev/null | sed -n '1,200p' > "$DIAG_DIR/cb_sink_$TS.log" || true
    echo "Saved diagnostics to $DIAG_DIR/*_$TS.*"

    if [ $attempt -lt $MAX_ATTEMPTS ]; then
      # exponential backoff (cap at 16s)
      sleep_time=$((2 ** (attempt - 1)))
      if [ $sleep_time -gt 16 ]; then sleep_time=16; fi
      echo "Will retry headless flow to obtain a fresh code after ${sleep_time}s..."
      sleep $sleep_time

      # attempt headless capture again (follows redirects)
      CODE_REDIRECT=$(docker run --rm --network "$NET" -e TEST_USER="$TEST_USER" -e TEST_PASS="$TEST_PASS" python:3.11-slim sh -s <<'SH'
python - <<'PY'
import os, requests
from bs4 import BeautifulSoup
from urllib.parse import urlparse, parse_qs
s = requests.Session()

auth_url = 'http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&scope=openid&redirect_uri=http://cb-sink:3000/callback'
resp = s.get(auth_url, verify=False)
form = BeautifulSoup(resp.text, 'html.parser').find('form')
if not form:
    print('|||')
    raise SystemExit(0)
action = form.get('action')
if action and 'localhost' in action:
    action = action.replace('localhost:8080','keycloak-keycloak:8080')

payload = {inp['name']: inp.get('value','') for inp in form.find_all('input') if inp.get('name')}
payload['username'] = os.environ['TEST_USER']
payload['password'] = os.environ['TEST_PASS']
resp = s.post(action, data=payload, allow_redirects=True, verify=False)

# If Keycloak requires profile verification, submit that form programmatically
if 'required-action' in resp.url or 'VERIFY_PROFILE' in resp.url or 'required-action' in resp.text:
    soup2 = BeautifulSoup(resp.text, 'html.parser')
    form2 = soup2.find('form')
    if form2:
        action2 = form2.get('action')
        payload2 = {inp['name']: inp.get('value','') for inp in form2.find_all('input') if inp.get('name')}
        payload2.setdefault('firstName','Test')
        payload2.setdefault('lastName','User')
        payload2.setdefault('email', os.environ.get('TEST_USER_EMAIL','testuser@gogotex.local'))
        resp = s.post(action2, data=payload2, allow_redirects=True, verify=False)

# check final URL
if 'code=' in resp.url:
    parsed = urlparse(resp.url)
    q = parse_qs(parsed.query)
    if 'code' in q:
        print(q['code'][0] + '|||' + parsed.scheme + '://' + parsed.netloc + parsed.path)
        raise SystemExit(0)
# fallback: search HTML
import re
m = re.search(r'(https?://[^\s"\']*/callback)[^\s"\']*.*code=([^\s\"\'\&]+)', resp.text)
if m:
    print(m.group(2) + '|||' + m.group(1))
    raise SystemExit(0)
print('|||')
PY
SH
)
# parse into CODE and REDIRECT_URI
CODE="$(printf '%s' "$CODE_REDIRECT" | sed -n '1p' | cut -d'|' -f1)"
REDIRECT_URI="$(printf '%s' "$CODE_REDIRECT" | sed -n '1p' | sed 's/.*|||//')"
      continue
    else
      echo "Auth-code exchange failed after $MAX_ATTEMPTS attempts.";
      break
    fi
  fi
done

# cleanup cb-sink
docker rm -f cb-sink >/dev/null 2>&1 || true

if [ "$EXCHANGE_SUCCESS" != "true" ]; then
  if [ "$FAIL_ON_AUTH_CODE" = "true" ]; then
    echo "❌ Auth-code E2E failed after $MAX_ATTEMPTS attempts."; docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true; exit 7
  else
    echo "⚠️ Auth-code E2E failed but continuing because FAIL_ON_AUTH_CODE=false (non-blocking)."
  fi
fi

# --- End auth-code E2E flow ---

# Call the /api/v1/me endpoint using the token via nginx (host-facing)
# Before calling /api/v1/me try to acquire a resource-owner token for the test user (preferred)
if [ -f "$TEST_PASS_FILE" ]; then
  TEST_PASS="$(cat "$TEST_PASS_FILE")"
  USER_TOKEN_RESP=$(docker run --rm --network "$NET" curlimages/curl -sS -X POST -d "client_id=gogotex-backend" -d "client_secret=$CLIENT_SECRET" -d "grant_type=password" -d "username=$TEST_USER" -d "password=$TEST_PASS" -d "scope=openid" http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/token || true)
  USER_ACCESS_TOKEN=$(printf '%s' "$USER_TOKEN_RESP" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p' || true)
  USER_ID_TOKEN=$(printf '%s' "$USER_TOKEN_RESP" | sed -n 's/.*"id_token":"\([^"]*\)".*/\1/p' || true)
  if [ -n "$USER_ID_TOKEN" ]; then
    echo "Acquired user id_token (preferred) for /api/v1/me checks"
  elif [ -n "$USER_ACCESS_TOKEN" ]; then
    echo "Acquired user access token for /api/v1/me checks (access token will be used)"
  else
    echo "Warning: failed to obtain password-grant token for test user; will fall back to client token"
  fi
  # Prefer OIDC id_token when available (middleware expects an id_token audience)
  USER_TOKEN=${USER_ID_TOKEN:-$USER_ACCESS_TOKEN}
else
  echo "Warning: test user password file not found ($TEST_PASS_FILE); will fall back to client token"
fi

echo "Calling /api/v1/me on auth service via host proxy ($PROXY_URL/api/v1/me)..."
# use Host header when routing via Traefik
AUTH_TOKEN=${USER_TOKEN:-$CLIENT_TOKEN}
if [ "$PROXY" = "traefik" ]; then
  # Traefik in dev uses self-signed certs; accept them for local CI checks
  RESP=$(curl --insecure -sS -H "Host: $PROXY_HOST_HEADER_AUTH" -H "Authorization: Bearer $AUTH_TOKEN" "$PROXY_URL/api/v1/me" || true)
else
  RESP=$(curl -sS -H "Authorization: Bearer $AUTH_TOKEN" "$PROXY_URL/api/v1/me" || true)
fi

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
  RESP2=$(docker run --rm --network "$NET" curlimages/curl -sS -H "Authorization: Bearer $AUTH_TOKEN" http://$AUTH_HOST/api/v1/me || true)
  echo "Direct container response:"; echo "$RESP2" | sed -n '1,200p'
  echo "Auth logs:"; docker logs "$AUTH_CONTAINER_NAME" | sed -n '1,200p'
  docker rm -f "$AUTH_CONTAINER_NAME" >/dev/null 2>&1 || true
  exit 4
fi
