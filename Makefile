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

.PHONY: ci-local
ci-local:
	@echo "Running local CI: prefer 'act' if available, otherwise Docker Compose CI"
	@if command -v act >/dev/null 2>&1; then \
		act --workflows .github/workflows/go-auth-ci.yml || true; \
	else \
		docker compose -f docker-compose.ci.yml run --rm ci; \
	fi

.PHONY: ci-integration
ci-integration:
	chmod +x scripts/ci/auth-integration-test.sh
	./scripts/ci/auth-integration-test.sh

.PHONY: auth-image
auth-image:
	docker build -t gogotex-auth:local backend/go-services
