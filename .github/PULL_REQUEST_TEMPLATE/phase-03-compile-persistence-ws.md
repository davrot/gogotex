## Summary

This PR completes Phase‑03: reliable compile → preview → persistence → realtime flow.

What's included
- Persist compiled artifacts (PDF + .synctex.gz) to MinIO and compile metadata to Mongo
- Publish compile metadata to Redis (`compile:updates`) so `yjs-server` can cache & broadcast
- Frontend `EditorPage` WebSocket listener consumes `{ type: 'compile-update' }` and auto-refreshes preview + SyncTeX map
- Playwright E2E: persistence → MinIO + Mongo → yjs replication test (integration)
- Fast frontend unit test for `EditorPage` WebSocket `compile-update` handling (Vitest + Testing Library)
- Backend unit test: `persistCompileFunc` publishes to Redis (miniredis)

Why
- Makes compile/preview UX reliable and real‑time for editor clients
- Adds durable persistence for artifacts so E2E tests become deterministic
- Adds regression coverage for the realtime replication path

Testing
- Unit: `npm run test:unit` (frontend)
- E2E: `npm run test:e2e` (Playwright) — includes new `persistence → yjs` integration test (skips if `yjs-server` not reachable)
- Backend tests: run in CI (includes Redis `miniredis` test)

Checklist
- [x] Persist compile artifacts (MinIO) + metadata (Mongo)
- [x] Publish compile metadata to Redis (`compile:updates`)
- [x] yjs-server: subscribe to `compile:updates`, cache and broadcast `compile-update`
- [x] Frontend: auto-refresh preview & SyncTeX map on `compile-update`
- [x] Playwright E2E: editor + compile + SyncTeX + realtime (integration)
- [x] Frontend unit test for WS handler
- [x] Backend unit test for Redis publish

Notes for reviewers
- CI must run services (MinIO, MongoDB, Redis, yjs-server) for the integration test to pass.
- The Playwright integration test will be skipped when `yjs-server` isn't reachable — safe for local dev.

How to validate locally
1. Start compose (`./gogotex-support-services/up_all.sh`) with MinIO / Mongo / Redis / yjs-server
2. Start backend + frontend
3. Run `npm run test:e2e` (Playwright) — the new test will run if `yjs-server` is reachable

Related
- Closes: Phase‑03 acceptance items
- Branch: `feat/phase-03-compile-persistence-ws`

---

/cc @team/frontend @team/backend
