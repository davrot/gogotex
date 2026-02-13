FROM node:20-alpine AS build
WORKDIR /app

# Allow overriding Vite envs at build time (use --build-arg VITE_* when building)
ARG VITE_KEYCLOAK_URL
ARG VITE_AUTH_URL
ARG VITE_REDIRECT_URI
ENV VITE_KEYCLOAK_URL=${VITE_KEYCLOAK_URL}
ENV VITE_AUTH_URL=${VITE_AUTH_URL}
ENV VITE_REDIRECT_URI=${VITE_REDIRECT_URI}

COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund || true
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
