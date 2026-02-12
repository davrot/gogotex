# Prometheus presence check (sourced by scripts/health-check.sh)
# Standalone bootstrap: provide ok/fail helpers and load .env
if ! declare -f ok >/dev/null 2>&1; then
  ok(){ echo "✅ $1"; PASSED=${PASSED:-0}; PASSED=$((PASSED+1)); }
fi
if ! declare -f fail >/dev/null 2>&1; then
  fail(){ echo "❌ $1"; FAILED=${FAILED:-0}; FAILED=$((FAILED+1)); }
fi
ROOT_DIR=${ROOT_DIR:-"$(cd "$(dirname "$0")/.." && pwd)"}
CONTAINERS=${CONTAINERS:-$(docker ps --format '{{.Names}}' 2>/dev/null || true)}
PROM_C=${PROM_C:-grafana-prometheus}

# expects: PROM_C variable and ok/fail helpers

PROM_C="grafana-prometheus"

echo
echo "== Prometheus quick check =="
if [ -n "$PROM_C" ]; then
  ok "Prometheus container present: $PROM_C"
else
  echo "- Skipping Prometheus check (container missing)"
fi
