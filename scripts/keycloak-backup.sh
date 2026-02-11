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

# Keycloak backup script
# - Dumps Postgres DB used by Keycloak (pg_dump)
# - Exports Keycloak realm(s) using kc.sh export
# Usage:
#   ./scripts/keycloak-backup.sh --out ./backups

OUT_DIR="${1:-./gogotex-support-services/keycloak-service/backup}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUT_DIR"

PG_CONTAINER=${PG_CONTAINER:-keycloak-postgres}
KC_CONTAINER=${KC_CONTAINER:-keycloak-keycloak}
PG_USER=${PG_USER:-keycloak}
PG_DB=${PG_DB:-keycloak}

echo "Backing up Keycloak Postgres DB from container '$PG_CONTAINER'..."
PG_DUMP_FILE="$OUT_DIR/keycloak_db_$TIMESTAMP.sql"
# pg_dump to stdout and capture on host
docker exec "$PG_CONTAINER" pg_dump -U "$PG_USER" "$PG_DB" > "$PG_DUMP_FILE"
echo "Postgres dump saved to $PG_DUMP_FILE"

# Export Keycloak realm(s)
echo "Exporting Keycloak data using kc.sh..."
EXPORT_DIR_IN_CONTAINER="/tmp/keycloak-export-$TIMESTAMP"
docker exec "$KC_CONTAINER" mkdir -p "$EXPORT_DIR_IN_CONTAINER"
# Use kc.sh export (Quarkus distribution)
docker exec "$KC_CONTAINER" /opt/keycloak/bin/kc.sh export --dir "$EXPORT_DIR_IN_CONTAINER" || true

EXPORT_TARBALL="$OUT_DIR/keycloak_export_$TIMESTAMP.tar.gz"
docker exec "$KC_CONTAINER" tar -C "$EXPORT_DIR_IN_CONTAINER" -czf /tmp/keycloak-export-$TIMESTAMP.tar.gz . || true
docker cp "$KC_CONTAINER":/tmp/keycloak-export-$TIMESTAMP.tar.gz "$EXPORT_TARBALL" || true
# Cleanup inside container
docker exec "$KC_CONTAINER" rm -rf "$EXPORT_DIR_IN_CONTAINER" /tmp/keycloak-export-$TIMESTAMP.tar.gz || true

if [ -f "$EXPORT_TARBALL" ]; then
  echo "Keycloak export saved to $EXPORT_TARBALL"
else
  echo "Warning: Keycloak export did not produce artifacts. Check Keycloak logs or permissions." >&2
fi

echo "Backup completed. Files in: $OUT_DIR"
exit 0
