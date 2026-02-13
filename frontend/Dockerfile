FROM node:20-alpine AS build
WORKDIR /app

# Accept build args and write a .env file (Vite reads .env at build time).
# We avoid setting ENV for potentially sensitive keys to reduce secret-scan noise.
ARG VITE_KEYCLOAK_URL
ARG VITE_KEYCLOAK_REALM
ARG VITE_KEYCLOAK_CLIENT_ID
ARG VITE_AUTH_URL
ARG VITE_REDIRECT_URI

# Create a .env that Vite will pick up during `npm run build`.
RUN printf "VITE_KEYCLOAK_URL=%s\nVITE_KEYCLOAK_REALM=%s\nVITE_KEYCLOAK_CLIENT_ID=%s\nVITE_AUTH_URL=%s\nVITE_REDIRECT_URI=%s\n" "${VITE_KEYCLOAK_URL:-}" "${VITE_KEYCLOAK_REALM:-}" "${VITE_KEYCLOAK_CLIENT_ID:-}" "${VITE_AUTH_URL:-}" "${VITE_REDIRECT_URI:-}" > .env

COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund || true
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
# SPA fallback so client-side routes (e.g. /auth/callback) return index.html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
