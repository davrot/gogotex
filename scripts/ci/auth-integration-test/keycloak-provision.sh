#!/usr/bin/env bash
set -euo pipefail

# Run the repository's keycloak-setup.sh inside the Docker network so admin API
# calls succeed. Accepts optional network name as first arg; otherwise autodetects.

NET_ARG=${1:-}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

NET=${NET_ARG:-$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' keycloak-keycloak 2>/dev/null || true)}
if [ -z "$NET" ]; then
  echo "ERROR: could not determine Docker network for Keycloak" >&2
  exit 2
fi

echo "Provisioning Keycloak on network: $NET"

docker run --rm --network "$NET" -v "$ROOT_DIR":/workdir -w /workdir alpine:3.19 \
  sh -c "apk add --no-cache curl jq openssl bash >/dev/null 2>&1 && KC_INSECURE=false KC_HOST=http://keycloak-keycloak:8080/sso /workdir/scripts/keycloak-setup.sh"
