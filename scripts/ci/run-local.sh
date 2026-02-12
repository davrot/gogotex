#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

echo "== Go Auth local CI: start =="

# Ensure required tools
if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found in PATH. Install Docker to run CI locally." >&2
  exit 2
fi

# Run unit tests and build for Go services
echo "-> Running unit tests (backend/go-services)"
if [ -f "backend/go-services/Makefile" ]; then
  make -C backend/go-services test
  make -C backend/go-services build
else
  (cd backend/go-services && go test ./... -v && go build ./...)
fi

# Optionally run a lint step if tools are available
if command -v go vet >/dev/null 2>&1; then
  echo "-> Running go vet"
  go vet ./...
fi

# Run infrastructure health check (requires Docker infra up)
if [ -x scripts/health-check.sh ]; then
  echo "-> Running infrastructure health-check"
  ./scripts/health-check.sh
else
  echo "-> No health-check script found or not executable; skipping"
fi

# Optional integration tests (set RUN_INTEGRATION=true to run)
if [ "${RUN_INTEGRATION:-false}" = "true" ]; then
  echo "-> Running integration tests"
  ./scripts/ci/auth-integration-test.sh
else
  echo "-> Skipping integration tests (set RUN_INTEGRATION=true to enable)"
fi

echo "== Go Auth local CI: success =="
