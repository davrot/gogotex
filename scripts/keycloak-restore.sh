#!/usr/bin/env bash
set -euo pipefail

# Load environment from support .env if present (PG/KC credentials)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SUPPORT_ENV="$ROOT_DIR/gogotex-support-services/.env"
if [ -f "$SUPPORT_ENV" ]; then
  set -o allexport
  source "$SUPPORT_ENV"
  set +o allexport
fi

# Keycloak restore helper
# - Can restore Postgres SQL dump into keycloak Postgres container
# - Can optionally import realm JSON using Keycloak admin API
# Usage:
#   ./scripts/keycloak-restore.sh --sql path/to/dump.sql
#   ./scripts/keycloak-restore.sh --realm path/to/realm.json --kc-host http://localhost:8080

print_usage() {
  cat <<EOF
Usage:
  $0 --sql <dump.sql>            # Restore Postgres DB dump into keycloak Postgres
  $0 --realm <realm.json>        # Import realm JSON via Keycloak admin API (requires admin creds or KC_HOST env)

Environment variables:
  PG_CONTAINER    (default: keycloak-postgres)
  KC_CONTAINER    (default: keycloak-keycloak)
  PG_USER         (default: keycloak)
  KC_HOST         (e.g. http://localhost:8080 or http://keycloak-keycloak:8080/sso)
  KEYCLOAK_ADMIN, KEYCLOAK_ADMIN_PASSWORD

Note: Restoring a Postgres dump is destructive for the DB. Backup first!
EOF
}

if [ $# -eq 0 ]; then
  print_usage
  exit 1
fi

PG_CONTAINER=${PG_CONTAINER:-keycloak-postgres}
PG_USER=${PG_USER:-keycloak}
KC_HOST=${KC_HOST:-}

while [ $# -gt 0 ]; do
  case "$1" in
    --sql) SQL_FILE="$2"; shift 2;;
    --realm) REALM_FILE="$2"; shift 2;;
    --kc-host) KC_HOST="$2"; shift 2;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown arg: $1"; print_usage; exit 1;;
  esac
done

if [ -n "${SQL_FILE:-}" ]; then
  if [ ! -f "$SQL_FILE" ]; then
    echo "SQL file not found: $SQL_FILE" >&2; exit 1
  fi
  echo "Restoring SQL dump into $PG_CONTAINER ..."
  cat "$SQL_FILE" | docker exec -i "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_USER"
  echo "Postgres restore complete"
fi

if [ -n "${REALM_FILE:-}" ]; then
  if [ -z "$KC_HOST" ]; then
    echo "KC_HOST is required to import realm JSON (set env KC_HOST or pass --kc-host)" >&2
    exit 1
  fi
  if [ ! -f "$REALM_FILE" ]; then
    echo "Realm file not found: $REALM_FILE" >&2; exit 1
  fi

  echo "Importing realm via admin API ($KC_HOST)..."
  # Retrieve admin token
  ADMIN=${KEYCLOAK_ADMIN:-admin}
  ADMIN_PASS=${KEYCLOAK_ADMIN_PASSWORD:-}
  if [ -z "$ADMIN_PASS" ]; then
    echo "KEYCLOAK_ADMIN_PASSWORD must be set in the environment to import realm" >&2
    exit 1
  fi

  TOKEN_RESP=$(curl -s -S -X POST -d "client_id=admin-cli" -d "username=$ADMIN" -d "password=$ADMIN_PASS" -d "grant_type=password" "$KC_HOST/realms/master/protocol/openid-connect/token")
  ACCESS_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token // empty')
  if [ -z "$ACCESS_TOKEN" ]; then
    echo "Failed to obtain admin token: $TOKEN_RESP" >&2; exit 1
  fi

  curl -s -S -X POST -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" --data-binary "@${REALM_FILE}" "$KC_HOST/admin/realms" || true
  echo "Realm import request submitted (check admin console or logs for issues)"
fi

exit 0
