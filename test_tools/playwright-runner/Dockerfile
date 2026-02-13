# Cached Playwright test image for faster CI / local runs
# - Pre-installs npm deps and Playwright browsers so test runs don't re-download on every run
# - Exposes a small helper at /prebaked_node_modules which the runner can copy into the mounted project

FROM mcr.microsoft.com/playwright:latest

WORKDIR /prebake

# Copy only package files to maximize layer cache (allow building with `frontend` as context)
COPY package.json package-lock.json* ./

# Install deps and browsers once at image build time
RUN npm ci --no-audit --no-fund && npx playwright install --with-deps \
    && cp -a node_modules /prebaked_node_modules

# Helpful metadata
LABEL org.gogotex.playwright.cached="true" \
      org.gogotex.maintainer="gogotex-dev"

# Default workdir when running tests
WORKDIR /app

# Entrypoint is a simple helper; it will copy prebaked node_modules into the mounted /app if missing
# and then run whatever command you pass (e.g. `sh -c "npm run test:e2e"`).
ENTRYPOINT ["/bin/sh","-c","cp -a /prebaked_node_modules /app/node_modules 2>/dev/null || true; exec \"$@\""]
CMD ["/bin/sh"]
