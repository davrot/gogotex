#!/usr/bin/env bash
set -euo pipefail

# Build runner image (Makefile target) then run the auth integration test inside it.
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

# Build the runner image if not present
if ! docker image inspect gogotex/integration-runner:latest >/dev/null 2>&1; then
  echo "Building integration-runner image..."
  make integration-runner-image
fi

# Run the integration script inside the prepared runner image. The repo is
# mounted and the Docker socket forwarded so the runner can start containers.
docker run --rm -v "$ROOT_DIR":"$ROOT_DIR" -w "$ROOT_DIR" -v /var/run/docker.sock:/var/run/docker.sock --network tex-network \
  -e RUN_INTEGRATION_DOCKER=true -e INTEGRATION_IN_DOCKER=1 \
  gogotex/integration-runner:latest \
  -lc "set -euo pipefail; cd '$ROOT_DIR'; bash ./scripts/ci/auth-integration-test.sh $*"
