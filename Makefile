# Convenience Makefile for common infra tasks

.PHONY: smoke-test keycloak-smoke

# Run full Keycloak smoke test locally (uses docker compose and scripts)
smoke-test:
	chmod +x scripts/ci/keycloak-smoke-test.sh
	./scripts/ci/keycloak-smoke-test.sh

# Alias for Keycloak smoke test
keycloak-smoke: smoke-test

.PHONY: minio-init
minio-init:
	chmod +x scripts/minio-init.sh
	./scripts/minio-init.sh

.PHONY: mongo-init
mongo-init:
	chmod +x scripts/mongo-init-recreate.sh
	./scripts/mongo-init-recreate.sh

.PHONY: redis-fix-perms
redis-fix-perms:
	chmod +x scripts/redis-fix-perms.sh
	./scripts/redis-fix-perms.sh
