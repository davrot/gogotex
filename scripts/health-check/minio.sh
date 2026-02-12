# MinIO checks (sourced by scripts/health-check.sh)
# expects: ok/fail helpers and MINIO_* env vars

echo
echo "== MinIO checks =="
if [ -n "$MINIO_C" ]; then
  # Prefer the unauthenticated health endpoint (explicitly checks service liveness)
  set +e
  HEALTH_CODE=$(docker run --rm --network tex-network curlimages/curl:8.4.0 -sS -o /dev/null -w "%{http_code}" http://minio-minio:9000/minio/health/live || true)
  set -e
  if [ "$HEALTH_CODE" = "200" ]; then
    ok "MinIO health endpoint OK (/minio/health/live)"
  else
    # fallback: root may return 403 for anonymous access — treat 403 as "service up, auth required"
    ROOT_CODE=$(docker run --rm --network tex-network curlimages/curl:8.4.0 -sS -o /dev/null -w "%{http_code}" http://minio-minio:9000/ || true)
    if [ "$ROOT_CODE" = "403" ]; then
      ok "MinIO HTTP endpoint responded (code 403 — anonymous access restricted)"
    elif [ "$ROOT_CODE" != "000" ]; then
      ok "MinIO HTTP endpoint responded (code $ROOT_CODE)"
    else
      fail "MinIO endpoint not responding on http://minio-minio:9000/"
    fi
  fi

  # --- authenticated checks: verify credentials and optional bucket presence ---
  MINIO_USER=${MINIO_ROOT_USER:-${MINIO_ACCESS_KEY:-admin}}
  MINIO_PASS=${MINIO_ROOT_PASSWORD:-${MINIO_SECRET_KEY:-changeme_minio}}

  set +e
  docker run --rm --network tex-network --entrypoint /bin/sh minio/mc -c "mc alias set tmp http://minio-minio:9000 $MINIO_USER $MINIO_PASS >/dev/null 2>&1 && mc ls tmp >/dev/null 2>&1"
  AUTH_OK=$?
  set -e

  if [ $AUTH_OK -eq 0 ]; then
    ok "MinIO authenticated API reachable (credentials valid)"

    # If MINIO_BUCKET is configured, ensure it exists
    if [ -n "${MINIO_BUCKET:-}" ]; then
      set +e
      docker run --rm --network tex-network --entrypoint /bin/sh minio/mc -c "mc alias set tmp http://minio-minio:9000 $MINIO_USER $MINIO_PASS >/dev/null 2>&1 && mc ls tmp/${MINIO_BUCKET} >/dev/null 2>&1"
      BUCKET_OK=$?
      set -e
      if [ $BUCKET_OK -eq 0 ]; then
        ok "MinIO bucket '${MINIO_BUCKET}' present"
      else
        fail "MinIO bucket '${MINIO_BUCKET}' not found"
      fi
    fi
  else
    fail "MinIO authentication failed with provided credentials"
  fi
else
  echo "- Skipping MinIO checks (container missing)"
fi
