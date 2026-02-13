# auth-integration-test sub-scripts

This folder contains focused steps extracted from the monolithic `scripts/ci/auth-integration-test.sh` to improve maintainability and make CI orchestration clearer.

Files:
- `playwright.sh` — runs the Playwright browser E2E inside the `tex-network` using the official Playwright Docker image. Accepts env vars: PLAYWRIGHT_BASE_URL, PLAYWRIGHT_KEYCLOAK, PLAYWRIGHT_REDIRECT_URI, TEST_USER, TEST_PASS.

Usage:
- The top-level `scripts/ci/auth-integration-test.sh` calls these sub-scripts and provides a shell-level timeout (`PLAYWRIGHT_RUN_TIMEOUT`).
- Keep changes small — add more sub-scripts (e.g. `keycloak.sh`, `infra_up.sh`) if the main script continues to grow.