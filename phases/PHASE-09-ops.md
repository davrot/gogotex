# Phase 09: Replica & Distributed Ops (MongoDB, Redis, MinIO)

**Duration**: 2–3 days (per service; parallel work possible)

## Goal
Move replica / distributed setup out of Phase 1 and implement robust, tested replication for MongoDB, Redis, and MinIO with clear acceptance criteria, backups, and failover/runbooks.

---

## Scope
- MongoDB: initialize and test 3-node replica set, backups and restore, failover tests
- Redis: configure replication (or Sentinel/Cluster), secure and test promotion/failover, backups
- MinIO: configure distributed mode (4 nodes), initialize buckets, verify data durability and healing
- Monitoring: add Prometheus scrape targets + alerts for replication lag and node failures
- Documentation: runbooks for failover and recovery, test procedures, and CI checks

---

## Prerequisites
- Access to repository and infra stack (compose files under `gogotex-support-services/`)
- Working single-node deployments validated from Phase 1
- Sufficient resources for running multiple nodes locally or in CI (recommended: 8GB+)

---

## High-level Tasks

### MongoDB replica set (3 nodes)
- [ ] Add/enable 3-node replica set in compose (primary + 2 secondaries)
- [ ] Provide `scripts/mongodb-replica-init.js` to initiate `rs.initiate()` and create admin user
- [ ] Validate authentication + user existence on all members
- [ ] Implement backup script using `mongodump` and restore using `mongorestore`
- [ ] Add health checks and Prometheus exporter for replication metrics

**Acceptance criteria**
- `rs.status()` reports 3 members, one PRIMARY, two SECONDARY
- Failover test: stop the primary, within 30s-60s a new PRIMARY is elected, writes succeed to new primary
- Backup/restore: perform dump & restore to a temporary DB and verify data integrity

**Verification steps**
1. `docker-compose up` for MongoDB nodes
2. Run `mongosh` to inspect `rs.status()` and check replication
3. Inject a test write, stop primary container, ensure write continues on new PRIMARY

---

### Redis replication / high availability
- [ ] Decide on approach: simple master+replica (replicaof) or configure Sentinel / Redis Cluster for auto-promotion
- [ ] Add compose services for replicas and optional Sentinel instances
- [ ] Implement read/write tests and a promotion test (simulate master failure)
- [ ] Add backup procedure (RDB/AOF) and restore instructions
- [ ] Add Prometheus exporter and alerting for replication lag and down nodes

**Acceptance criteria**
- Replication stream established: `INFO replication` shows replicas connected
- Promotion test: stop master; replica is promoted or Sentinel triggers failover; service recovers and accepts writes

**Verification steps**
1. `redis-cli -a <pass> INFO replication`
2. Write keys to master, verify replication on replicas
3. Stop master, verify failover and write capability resumes

---

### MinIO distributed storage (4 nodes)
- [ ] Convert MinIO compose to 4-node distributed layout (4 data nodes)
- [ ] Add `gogotex-minio-init` (or reuse current) to create buckets and policies via `mc`
- [ ] Implement bucket health checks and `mc` based tests for object PUT/GET
- [ ] Test redundancy & healing: take a node down and verify data availability & automatic healing
- [ ] Add monitoring of MinIO metrics (Prometheus exporter)

**Acceptance criteria**
- Distributed MinIO forms a cluster and reports all nodes up
- Buckets created and objects are readable after node failure & recovery
- Bucket list and policies are intact after re-bootstrap

**Verification steps**
1. Start 4 MinIO nodes; run `mc admin service status` and `mc ls` to verify
2. Put objects, stop one node, ensure GET still works
3. Restart node and verify cluster heals (objects rebalanced)

---

## Monitoring & Alerts
- [ ] Add Prometheus scrape targets (MongoDB exporter, Redis exporter, MinIO exporter)
- [ ] Add alerts for:
  - `mongo_replication_lag > threshold`
  - Redis replica disconnected
  - MinIO node down or degraded

---

## Backups & Restore
- Provide documented and tested scripts for:
  - `scripts/mongo-backup.sh` / `scripts/mongo-restore.sh` (mongodump/mongorestore)
  - `scripts/redis-backup.sh` (copy RDB/AOF) and restore procedure
  - `scripts/minio-backup.sh` (periodic `mc cp --recursive` to backup bucket data)

---

## Runbook & Tests
- Create a **Failover Runbook**: step-by-step actions for recovering from node failure for each service
- Create automated smoke tests (CI optional) for replica behavior — can be gated behind a `replica` job (not required for main CI)

---

## Rollout Plan
1. Implement and test locally using compose and `scripts/` helpers
2. Add monitoring, alerts, and backup automation
3. Validate failover tests manually and with automated tests
4. Merge to `main` behind a flag and monitor

---

## Estimated Time & Effort
- Implementation & testing: **2–3 days per service** if done sequentially, or **3–5 days** total if parallelized and resourced

---

## Notes & References
- Relevant files: `gogotex-support-services/compose.yaml`, `scripts/mongodb-replica-init.js`, `scripts/mongodb-init.js`
- Phase 1 checklist has been updated to postpone replica work to this phase (Phase 09)

---

## Checklist (Phase 09)
- [ ] MongoDB replica set implemented and tested
- [ ] Redis replication / HA implemented and tested
- [ ] MinIO distributed mode implemented and tested
- [ ] Backups and restores validated for each service
- [ ] Monitoring & alerts added and firing correctly
- [ ] Runbooks and automation documented

---

*End of Phase 09 plan.*
