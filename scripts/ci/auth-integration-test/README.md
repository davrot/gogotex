# auth-integration-test sub-scripts

This folder contains focused steps extracted from the monolithic `scripts/ci/auth-integration-test.sh` to improve maintainability and make CI orchestration clearer.

Files:
- `playwright.sh` — runs the Playwright browser E2E inside the `tex-network` using the official Playwright Docker image. Accepts env vars: PLAYWRIGHT_BASE_URL, PLAYWRIGHT_KEYCLOAK, PLAYWRIGHT_REDIRECT_URI, TEST_USER, TEST_PASS.

Usage:
- The top-level `scripts/ci/auth-integration-test.sh` calls these sub-scripts and provides a shell-level timeout (`PLAYWRIGHT_RUN_TIMEOUT`).
- Keep changes small — add more sub-scripts (e.g. `keycloak.sh`, `infra_up.sh`) if the main script continues to grow.

Quick examples (local, verbose):

- Run the full integration with verbose Playwright output (recommended for debugging):

  PLAYWRIGHT_VERBOSE=true PLAYWRIGHT_PER_TEST_TIMEOUT=60000 PLAYWRIGHT_RUN_TIMEOUT=180 RUN_PLAYWRIGHT=true CLEANUP=true ./scripts/ci/auth-integration-test.sh

- Run integration but skip Playwright (fast):

  RUN_PLAYWRIGHT=false ./scripts/ci/auth-integration-test.sh

Timeout semantics:
- `PLAYWRIGHT_PER_TEST_TIMEOUT` (ms) controls Playwright's per-test timeout.
- `PLAYWRIGHT_RUN_TIMEOUT` (s) is an outer shell-level timeout enforced by `timeout` (preferred) or a watcher; it kills the Playwright run to prevent CI hangs.

Where artifacts land:
- Playwright writes test artifacts (screenshots / traces / junit) into `frontend/test-results`.
- The integration script saves diagnostic logs under `test-output/` on failures.