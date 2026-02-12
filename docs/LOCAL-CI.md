# Running CI Locally

This document explains how to run the repository CI tasks locally using Docker.

Prerequisites
- Docker & Docker Compose installed
- (Optional) act - run GitHub Actions locally

Options
1) Run the helper script directly (recommended):

```bash
# from repo root
chmod +x ./scripts/ci/run-local.sh
./scripts/ci/run-local.sh
```

2) Use the Docker-based CI service (no extra installs other than Docker):

```bash
docker compose -f docker-compose.ci.yml up --build --abort-on-container-exit --exit-code-from ci
```

3) If you have `act` installed and prefer to run GH Actions locally (requires Docker too):

```bash
# runs the workflows locally (install act from https://github.com/nektos/act)
act -j build
```

Notes
- The script runs unit tests and builds the `backend/go-services` service, and runs the repository health-check (which requires Docker infra to be running).
- To also run end-to-end integration tests (Keycloak + MongoDB + auth service), set `RUN_INTEGRATION=true` in the environment before running the helper script. Example:

```bash
# run full CI including integration tests (keep infra running after tests unless CLEANUP=true)
RUN_INTEGRATION=true docker compose -f docker-compose.ci.yml up --build --abort-on-container-exit --exit-code-from ci
# or run the integration script directly and tear down infra when done:
CLEANUP=true ./scripts/ci/auth-integration-test.sh
```

- Use `.env` or `gogotex-support-services/.env` to provide required service credentials for Keycloak/Redis/MinIO when running the health-check.
- For reproducible CI runs, `docker-compose.ci.yml` mounts the repository and runs `scripts/ci/run-local.sh` inside a clean `golang:1.20` container.

Troubleshooting
- If tests need additional tools (e.g., `golangci-lint`), install them on your host or extend `docker/ci.Dockerfile`.
