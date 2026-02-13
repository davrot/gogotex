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
	DOCKER_BUILDKIT=1 docker build -t gogotex-auth:local backend/go-services

.PHONY: integration-runner-image
integration-runner-image:
	@echo "Building integration-runner image (ubuntu + docker + curl + jq)..."
	DOCKER_BUILDKIT=1 docker build -f scripts/ci/Dockerfile.integration -t gogotex/integration-runner:latest .
	@echo "Built gogotex/integration-runner:latest"

.PHONY: run-integration-in-docker
run-integration-in-docker:
	chmod +x scripts/ci/run-integration-in-docker.sh
	./scripts/ci/run-integration-in-docker.sh

.PHONY: install-buildx
install-buildx:
	@echo "Installing docker buildx to ~/.docker/cli-plugins (requires curl)"
	@mkdir -p ~/.docker/cli-plugins
	@curl -fsSL "https://github.com/docker/buildx/releases/download/v0.11.4/buildx-v0.11.4.linux-amd64" -o ~/.docker/cli-plugins/docker-buildx || true
	@chmod +x ~/.docker/cli-plugins/docker-buildx || true
	@echo "Done — run 'docker buildx version' to verify."
