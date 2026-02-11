#!/usr/bin/env bash
set -euo pipefail

# Fix Prometheus data directory so the Prometheus process can create and mmap
# files. This script is idempotent and safe to run multiple times.
# Best practice: use a local disk (ext4/xfs) for Prometheus TSDB; NFS is not
# supported by Prometheus and may corrupt data. See PHASE-01 notes.

PROM_DIR="./data-prometheus"
PROM_IMG="prom/prometheus:latest"

mkdir -p "$PROM_DIR"

# Remove stale files Prometheus will recreate
rm -f "$PROM_DIR/lock" "$PROM_DIR/queries.active" || true

# Attempt to detect container runtime uid/gid for Prometheus and chown
if command -v docker >/dev/null 2>&1; then
  echo "Detecting Prometheus runtime uid/gid from image $PROM_IMG..."
  PROM_UID=$(docker run --rm --entrypoint sh "$PROM_IMG" -c 'id -u prometheus 2>/dev/null || id -u nobody 2>/dev/null || id -u 2>/dev/null' 2>/dev/null || true)
  PROM_GID=$(docker run --rm --entrypoint sh "$PROM_IMG" -c 'id -g prometheus 2>/dev/null || id -g nobody 2>/dev/null || id -g 2>/dev/null' 2>/dev/null || true)

  if [[ -n "$PROM_UID" && -n "$PROM_GID" ]]; then
    echo "Found uid:gid $PROM_UID:$PROM_GID. Attempting chown on $PROM_DIR (may ask for sudo)."
    if command -v sudo >/dev/null 2>&1; then
      sudo chown -R "$PROM_UID:$PROM_GID" "$PROM_DIR" || echo "chown failed; falling back to permissive chmod"
    else
      chown -R "$PROM_UID:$PROM_GID" "$PROM_DIR" 2>/dev/null || echo "chown failed or requires sudo; falling back to permissive chmod"
    fi
  else
    echo "Could not detect Prometheus uid/gid from image. Falling back to permissive chmod."
  fi
fi

# Ensure writable and executable bits for dirs so Prometheus can create files.
# Use conservative permissions where possible but ensure functionality for dev.
if command -v sudo >/dev/null 2>&1; then
  sudo chmod -R a+rwX "$PROM_DIR" || true
  sudo chmod g+s "$PROM_DIR" || true
else
  chmod -R a+rwX "$PROM_DIR" || true
  chmod g+s "$PROM_DIR" || true
fi

cat <<'EOF'
✅ Prometheus data directory prepared.
Notes:
 - If you use NFS for $PROM_DIR, Prometheus warns that the filesystem is unsupported and this may lead to data corruption.
 - Recommended long-term fix: use a Docker named volume or a local host path on ext4/xfs and ensure UID/GID mapping is consistent with the Prometheus process user.
 - This script will remove stale lock/queries files and attempt a best-effort chown; run it before starting Prometheus.
EOF

