# GoGoLaTeX Infrastructure (Repository Layout & Quickstart)

This README explains where infrastructure manifests and scripts live in the repository and how to use them for local development.

Quick overview
- Support services (Keycloak, MinIO, Prometheus, Grafana, nginx, Postgres for Keycloak) live under `gogotex-support-services/`.
- Application services (realtime server, yjs server, Go services) live under `gogotex-services/`.
- Reusable operational scripts live under the top-level `scripts/` directory.

Important files
- `gogotex-support-services/compose.yaml` — primary docker compose for infra/support services
- `gogotex-support-services/.env.example` — example environment variables for support services (copy to `.env` and adjust)
- `scripts/keycloak-setup.sh` — automated Keycloak realm/client/user setup script
- `scripts/mongodb-init.js` — MongoDB initialization (creates collections & indexes)
- `scripts/mongodb-replica-init.js` — MongoDB replica set initialization script

Local quickstart (development)
1. Ensure `.env` exists: copy `gogotex-support-services/.env.example` to `gogotex-support-services/.env` and customize passwords and ports.

2. Start infra/support services:

```bash
cd /home/davrot/gogotex
docker compose -f gogotex-support-services/compose.yaml up -d
```

3. Wait for Keycloak to become ready and run the helper script (recommended):

```bash
# If Keycloak is exposed on host
KC_HOST=http://localhost:8080 ./scripts/keycloak-setup.sh

# Or, if you don't expose ports to host, run inside Docker network: 
# docker exec -it <keycloak-container> /opt/keycloak/bin/kc.sh ... or copy and run the script inside a container on the same network.
```

4. Verify services:
- Keycloak admin: http://localhost:8080 (if exposed)
- MinIO console: http://localhost:9001
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3001

Notes & recommendations
- The setup script `scripts/keycloak-setup.sh` is idempotent and safe for repeated runs in development.
- For production, **do not** use the example passwords in `.env`. Pin images to specific versions and use a secret management solution.
- If you prefer recreating the MongoDB replica set manually, see `scripts/mongodb-replica-init.js`.

Backup & migration
- Non-destructive migration path (recommended before any upgrade/change):
  1. Backup Postgres DB and Keycloak realm(s):
     - `./scripts/keycloak-backup.sh --out ./gogotex-support-services/keycloak-service/backup`
     - This runs `pg_dump` for the Keycloak DB and runs `kc.sh export` to capture realm JSON and server state.
  2. If you need to restore:
     - Restore DB: `./scripts/keycloak-restore.sh --sql backup/keycloak_db_<timestamp>.sql`
     - Import realm JSON: `./scripts/keycloak-restore.sh --realm backup/keycloak_export_<timestamp>/realm-<name>.json --kc-host http://localhost:8080`
  3. If liquibase checksum errors occur ("Validation Failed"), do not panic: create a DB backup first, then consider updating the `DATABASECHANGELOG` checksum entry or using Keycloak export/import; we can provide a helper script to repair checksums if you need it.

Test client & user
- The setup script will create or ensure a confidential client `gogotex-backend` with direct access grants enabled and generate a client secret. The secret is stored (developer convenience) at:
  - `gogotex-support-services/keycloak-service/client-secret_gogotex-backend.txt`
- To test the test user login manually:
  1. Get the client secret: `cat gogotex-support-services/keycloak-service/client-secret_gogotex-backend.txt`
  2. Run the token request (host):
     - `curl -k -X POST -d "client_id=gogotex-backend" -d "client_secret=<secret>" -d "username=testuser" -d "password=<test_password>" "https://localhost/sso/realms/gogotex/protocol/openid-connect/token"`
  3. Or, run inside Docker network if host access is not available:
     - `docker run --rm --network tex-network curlimages/curl -sS -X POST -d "client_id=gogotex-backend" -d "client_secret=<secret>" -d "username=testuser" -d "password=<test_password>" "http://keycloak-keycloak:8080/sso/realms/gogotex/protocol/openid-connect/token"`
- The setup script performs this verification automatically and prints a short success/failure message and access token snippet.

Running smoke tests locally
- The repository includes a smoke test that brings up a disposable Keycloak + Postgres stack, runs the setup, and verifies the token flow:

  1. Ensure Docker and Docker Compose are installed and you are in the repository root.
  2. Run the smoke test script directly (or use the Makefile shortcut):

     ```bash
     # Direct
     chmod +x scripts/ci/keycloak-smoke-test.sh
     ./scripts/ci/keycloak-smoke-test.sh

     # Using Makefile
     make smoke-test
     # or
     make keycloak-smoke
     ```

     The script will:
     - Start `keycloak-postgres` and `keycloak-keycloak` from `gogotex-support-services/keycloak-service`
     - Wait for Keycloak to respond
     - Run `scripts/keycloak-setup.sh` inside a container on the same network
     - Run `scripts/keycloak-test-client.sh --mode client_credentials` to verify token issuance for the confidential client. Use `--mode password` to test a user password grant if required (may be flaky depending on realm configuration).

  3. Troubleshooting tips:
     - If the test fails with network/DNS errors, ensure the compose network `tex-network` exists and the compose files specify it.
     - If Keycloak fails to start due to DB issues, inspect the Postgres container logs (`docker logs keycloak-postgres`) and refer to the backup/restore guidance above.
     - For HTTPS/self-signed certs, set `KC_INSECURE=true` in the environment when running the setup script.

Troubleshooting
- If the Keycloak script cannot find the server, ensure `KC_HOST` points to the correct URL (e.g., `http://localhost:8080` or `http://keycloak:8080`).
- If running the setup from the host but Keycloak ports are not published, run the setup script from within a container connected to the same Docker network.

Contact
- For infra questions, see `phases/PHASE-01-infrastructure.md` for the canonical checklist and expected verification steps.
