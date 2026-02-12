FROM golang:1.24

# Install common utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git jq bash && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# By default we expect repo mounted into /workspace
ENTRYPOINT ["/workspace/scripts/ci/run-local.sh"]
