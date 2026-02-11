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

Troubleshooting
- If the Keycloak script cannot find the server, ensure `KC_HOST` points to the correct URL (e.g., `http://localhost:8080` or `http://keycloak:8080`).
- If running the setup from the host but Keycloak ports are not published, run the setup script from within a container connected to the same Docker network.

Contact
- For infra questions, see `phases/PHASE-01-infrastructure.md` for the canonical checklist and expected verification steps.
