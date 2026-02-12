# Prometheus presence check (sourced by scripts/health-check.sh)
# expects: PROM_C variable and ok/fail helpers

echo
echo "== Prometheus quick check =="
if [ -n "$PROM_C" ]; then
  ok "Prometheus container present: $PROM_C"
else
  echo "- Skipping Prometheus check (container missing)"
fi
