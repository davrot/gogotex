#!/usr/bin/env bash
set -euo pipefail

# Load environment from support .env if present
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SUPPORT_ENV="$ROOT_DIR/gogotex-support-services/.env"
if [ -f "$SUPPORT_ENV" ]; then
  set -o allexport
  source "$SUPPORT_ENV"
  set +o allexport
fi

# keycloak-test-client.sh
# Verifies a confidential client's token issuance via one of two modes:
#  - client_credentials (default): client_id + client_secret => access token
#  - password: resource-owner password credentials (username+password)
# Usage: ./scripts/keycloak-test-client.sh --mode client_credentials --kc-host http://keycloak-keycloak:8080/sso --client-id gogotex-backend --secret-file ./gogotex-support-services/keycloak-service/client-secret_gogotex-backend.txt

KC_HOST=${KC_HOST:-http://localhost:8080/sso}
CLIENT_ID=${CLIENT_ID:-gogotex-backend}
SECRET_FILE=${SECRET_FILE:-./gogotex-support-services/keycloak-service/client-secret_${CLIENT_ID}.txt}
MODE=${MODE:-client_credentials}   # client_credentials | password
USER=${USER:-testuser}
PASSWORD=${PASSWORD:-}
INSECURE_FLAG=${INSECURE_FLAG:-}

# Parse CLI args
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="$2"; shift 2;;
    --kc-host) KC_HOST="$2"; shift 2;;
    --client-id) CLIENT_ID="$2"; shift 2;;
    --secret-file) SECRET_FILE="$2"; shift 2;;
    --user) USER="$2"; shift 2;;
    --password) PASSWORD="$2"; shift 2;;
    --insecure) INSECURE_FLAG=--insecure; shift 1;;
    -h|--help) echo "Usage: $0 [--mode client_credentials|password] [--kc-host URL] [--client-id id] [--secret-file path] [--user name] [--password pwd] [--insecure]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

if [ "$MODE" = "password" ] && [ -z "$PASSWORD" ]; then
  echo "Password not provided; attempting to read from interactive prompt"
  read -s -p "Password for user $USER: " PASSWORD
  echo
fi

if [ ! -f "$SECRET_FILE" ]; then
  echo "Client secret file not found: $SECRET_FILE" >&2
  exit 2
fi
CLIENT_SECRET=$(cat "$SECRET_FILE")

if [ "$MODE" = "client_credentials" ]; then
  echo "Testing client_credentials token request to $KC_HOST for client $CLIENT_ID"
  RESPONSE=$(curl ${INSECURE_FLAG} -sS -X POST -d "client_id=$CLIENT_ID" -d "client_secret=$CLIENT_SECRET" -d "grant_type=client_credentials" "$KC_HOST/realms/gogotex/protocol/openid-connect/token" || true)
else
  echo "Testing password token request to $KC_HOST for user $USER with client $CLIENT_ID"
  RESPONSE=$(curl ${INSECURE_FLAG} -sS -X POST -d "client_id=$CLIENT_ID" -d "client_secret=$CLIENT_SECRET" -d "username=$USER" -d "password=$PASSWORD" -d "grant_type=password" "$KC_HOST/realms/gogotex/protocol/openid-connect/token" || true)
fi

if [ -n "$RESPONSE" ] && [ "$(echo "$RESPONSE" | jq -r '.access_token // empty' 2>/dev/null)" != "" ]; then
  echo "✅ Token retrieval successful"
  echo "Access token (short): $(echo "$RESPONSE" | jq -r '.access_token' | cut -c1-60)..."
  exit 0
else
  echo "❌ Token retrieval failed"
  echo "Response:"
  echo "$RESPONSE" | sed -n '1,40p'
  exit 3
fi
