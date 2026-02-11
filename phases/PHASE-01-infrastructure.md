# Phase 1: Infrastructure & Foundation

**Duration**: 3-5 days  
**Goal**: Set up complete Docker infrastructure with all services running and healthy

---

## Prerequisites

- [ ] Docker and Docker Compose installed (`docker --version`, `docker-compose --version`)
- [ ] Port availability check: 80, 443, 3000, 5000, 8080, 9000, 27017, 6379, 8081
- [ ] At least 8GB RAM available for Docker
- [ ] 20GB free disk space

---

## Task 1: Project Structure Setup (30 min)

### 1.1 Verify Repository Layout

The repository has been organized into two main areas:
- `gogotex-support-services/` — infrastructure and support services (Keycloak, MinIO, Prometheus, Grafana, nginx, DBs)
- `gogotex-services/` — application and realtime services (yjs-server, node services, go services)

Create any missing local helper scripts and directories used by the infra:

```bash
cd /home/davrot/gogotex
# Operational scripts
mkdir -p scripts
# Service manifests and support stack
mkdir -p gogotex-support-services/config gogotex-support-services/scripts
# Application services (if needed)
mkdir -p gogotex-services
```

**Verification**:
```bash
ls -la gogotex-support-services gogotex-services scripts
```

---

## Task 2: Docker Compose - Base Configuration (1 hour)

### 2.1 Create Main Docker Compose File

Compose: `gogotex-support-services/compose.yaml` (support/infrastructure stack)

> Note: service-specific compose files can be found under `gogotex-services/` for application components.

```yaml
version: '3.8'

# GoGoLaTeX - Main Docker Compose Configuration
# This file orchestrates all services for the collaborative LaTeX editor

networks:
  gogolatex-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16

volumes:
  # MongoDB data
  gogolatex-mongodb-data-1:
  gogolatex-mongodb-data-2:
  gogolatex-mongodb-data-3:
  gogolatex-mongodb-config:
  
  # Redis data
  gogolatex-redis-data-master:
  gogolatex-redis-data-replica-1:
  gogolatex-redis-data-replica-2:
  
  # MinIO data (distributed)
  gogolatex-minio-data-1:
  gogolatex-minio-data-2:
  gogolatex-minio-data-3:
  gogolatex-minio-data-4:
  
  # Keycloak data
  gogolatex-keycloak-data:
  
  # Prometheus data
  prometheus-data:
  
  # Grafana data
  grafana-data:

services:
  # ============================================================================
  # MongoDB Replica Set (3 nodes)
  # ============================================================================
  
  gogolatex-mongodb-primary:
    image: mongo:8.0
    container_name: gogolatex-mongodb-primary
    hostname: gogolatex-mongodb-primary
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: ${MONGODB_ROOT_PASSWORD:-changeme_mongodb_root}
      MONGO_INITDB_DATABASE: gogolatex
    command: >
      mongod
      --replSet gogolatex
      --bind_ip_all
      --port 27017
    volumes:
      - gogolatex-mongodb-data-1:/data/db
      - gogolatex-mongodb-config:/data/configdb
      - ./scripts/mongodb-init.js:/docker-entrypoint-initdb.d/init.js:ro
    ports:
      - "27017:27017"
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.10
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 40s

  gogolatex-mongodb-secondary-1:
    image: mongo:8.0
    container_name: gogolatex-mongodb-secondary-1
    hostname: gogolatex-mongodb-secondary-1
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: ${MONGODB_ROOT_PASSWORD:-changeme_mongodb_root}
    command: >
      mongod
      --replSet gogolatex
      --bind_ip_all
      --port 27017
    volumes:
      - gogolatex-mongodb-data-2:/data/db
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.11
    depends_on:
      gogolatex-mongodb-primary:
        condition: service_healthy

  gogolatex-mongodb-secondary-2:
    image: mongo:8.0
    container_name: gogolatex-mongodb-secondary-2
    hostname: gogolatex-mongodb-secondary-2
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: ${MONGODB_ROOT_PASSWORD:-changeme_mongodb_root}
    command: >
      mongod
      --replSet gogolatex
      --bind_ip_all
      --port 27017
    volumes:
      - gogolatex-mongodb-data-3:/data/db
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.12
    depends_on:
      gogolatex-mongodb-primary:
        condition: service_healthy

  # MongoDB replica set initialization
  gogolatex-mongodb-init:
    image: mongo:8.0
    container_name: gogolatex-mongodb-init
    restart: "no"
    depends_on:
      gogolatex-mongodb-primary:
        condition: service_healthy
      gogolatex-mongodb-secondary-1:
        condition: service_started
      gogolatex-mongodb-secondary-2:
        condition: service_started
    networks:
      - gogolatex-network
    volumes:
      - ./scripts/mongodb-replica-init.js:/scripts/init.js:ro
    entrypoint: >
      bash -c "
        sleep 10 &&
        mongosh --host gogolatex-mongodb-primary -u admin -p ${MONGODB_ROOT_PASSWORD:-changeme_mongodb_root} --authenticationDatabase admin < /scripts/init.js
      "

  # ============================================================================
  # Redis Cluster (1 master + 2 replicas)
  # ============================================================================

  gogolatex-redis-master:
    image: redis:8.4-alpine
    container_name: gogolatex-redis-master
    hostname: gogolatex-redis-master
    restart: unless-stopped
    command: >
      redis-server
      --appendonly yes
      --appendfsync everysec
      --requirepass ${REDIS_PASSWORD:-changeme_redis}
      --maxmemory 2gb
      --maxmemory-policy allkeys-lru
      --save 900 1
      --save 300 10
      --save 60 10000
    volumes:
      - gogolatex-redis-data-master:/data
    ports:
      - "6379:6379"
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.20
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD:-changeme_redis}", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  gogolatex-redis-replica-1:
    image: redis:8.4-alpine
    container_name: gogolatex-redis-replica-1
    hostname: gogolatex-redis-replica-1
    restart: unless-stopped
    command: >
      redis-server
      --appendonly yes
      --requirepass ${REDIS_PASSWORD:-changeme_redis}
      --masterauth ${REDIS_PASSWORD:-changeme_redis}
      --replicaof gogolatex-redis-master 6379
    volumes:
      - gogolatex-redis-data-replica-1:/data
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.21
    depends_on:
      gogolatex-redis-master:
        condition: service_healthy

  gogolatex-redis-replica-2:
    image: redis:8.4-alpine
    container_name: gogolatex-redis-replica-2
    hostname: gogolatex-redis-replica-2
    restart: unless-stopped
    command: >
      redis-server
      --appendonly yes
      --requirepass ${REDIS_PASSWORD:-changeme_redis}
      --masterauth ${REDIS_PASSWORD:-changeme_redis}
      --replicaof gogolatex-redis-master 6379
    volumes:
      - gogolatex-redis-data-replica-2:/data
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.22
    depends_on:
      gogolatex-redis-master:
        condition: service_healthy

  # ============================================================================
  # MinIO Distributed Storage (4 nodes)
  # ============================================================================

  gogolatex-minio-1:
    image: minio/minio:latest
    container_name: gogolatex-minio-1
    hostname: gogolatex-minio-1
    restart: unless-stopped
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:-minioadmin}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD:-changeme_minio}
      MINIO_DISTRIBUTED_MODE_ENABLED: "yes"
      MINIO_DISTRIBUTED_NODES: "gogolatex-minio-{1...4}/data"
    command: server --console-address ":9001" http://gogolatex-minio-{1...4}/data
    volumes:
      - gogolatex-minio-data-1:/data
    ports:
      - "9000:9000"
      - "9001:9001"
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.30
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 10s
      timeout: 5s
      retries: 5

  gogolatex-minio-2:
    image: minio/minio:latest
    container_name: gogolatex-minio-2
    hostname: gogolatex-minio-2
    restart: unless-stopped
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:-minioadmin}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD:-changeme_minio}
      MINIO_DISTRIBUTED_MODE_ENABLED: "yes"
      MINIO_DISTRIBUTED_NODES: "gogolatex-minio-{1...4}/data"
    command: server --console-address ":9001" http://gogolatex-minio-{1...4}/data
    volumes:
      - gogolatex-minio-data-2:/data
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.31

  gogolatex-minio-3:
    image: minio/minio:latest
    container_name: gogolatex-minio-3
    hostname: gogolatex-minio-3
    restart: unless-stopped
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:-minioadmin}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD:-changeme_minio}
      MINIO_DISTRIBUTED_MODE_ENABLED: "yes"
      MINIO_DISTRIBUTED_NODES: "gogolatex-minio-{1...4}/data"
    command: server --console-address ":9001" http://gogolatex-minio-{1...4}/data
    volumes:
      - gogolatex-minio-data-3:/data
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.32

  gogolatex-minio-4:
    image: minio/minio:latest
    container_name: gogolatex-minio-4
    hostname: gogolatex-minio-4
    restart: unless-stopped
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:-minioadmin}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD:-changeme_minio}
      MINIO_DISTRIBUTED_MODE_ENABLED: "yes"
      MINIO_DISTRIBUTED_NODES: "gogolatex-minio-{1...4}/data"
    command: server --console-address ":9001" http://gogolatex-minio-{1...4}/data
    volumes:
      - gogolatex-minio-data-4:/data
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.33

  # MinIO client for bucket initialization
  gogolatex-minio-init:
    image: minio/mc:latest
    container_name: gogolatex-minio-init
    restart: "no"
    depends_on:
      gogolatex-minio-1:
        condition: service_healthy
    networks:
      - gogolatex-network
    entrypoint: >
      /bin/sh -c "
      sleep 5;
      mc alias set myminio http://gogolatex-minio-1:9000 ${MINIO_ROOT_USER:-minioadmin} ${MINIO_ROOT_PASSWORD:-changeme_minio};
      mc mb myminio/projects --ignore-existing;
      mc mb myminio/templates --ignore-existing;
      mc mb myminio/backups --ignore-existing;
      mc mb myminio/plugins --ignore-existing;
      mc anonymous set download myminio/templates;
      echo 'MinIO buckets created successfully';
      "

  # ============================================================================
  # Keycloak (Authentication)
  # ============================================================================

  gogolatex-keycloak:
    image: quay.io/keycloak/keycloak:26.0
    container_name: gogolatex-keycloak
    hostname: gogolatex-keycloak
    restart: unless-stopped
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: ${KEYCLOAK_ADMIN_PASSWORD:-changeme_keycloak}
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://gogolatex-keycloak-db:5432/keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: ${KEYCLOAK_DB_PASSWORD:-changeme_keycloak_db}
      KC_HOSTNAME: localhost
      KC_HOSTNAME_STRICT: "false"
      KC_HTTP_ENABLED: "true"
      KC_HEALTH_ENABLED: "true"
      KC_METRICS_ENABLED: "true"
    command: start-dev
    ports:
      - "8080:8080"
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.40
    depends_on:
      gogolatex-keycloak-db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health/ready"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  gogolatex-keycloak-db:
    image: postgres:16-alpine
    container_name: gogolatex-keycloak-db
    hostname: gogolatex-keycloak-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak
      POSTGRES_PASSWORD: ${KEYCLOAK_DB_PASSWORD:-changeme_keycloak_db}
    volumes:
      - gogolatex-keycloak-data:/var/lib/postgresql/data
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.41
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U keycloak"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ============================================================================
  # Monitoring: Prometheus + Grafana
  # ============================================================================

  prometheus:
    image: prom/prometheus:latest
    container_name: gogolatex-prometheus
    hostname: prometheus
    restart: unless-stopped
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    volumes:
      - ./config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.50

  grafana:
    image: grafana/grafana:latest
    container_name: gogolatex-grafana
    hostname: grafana
    restart: unless-stopped
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD:-changeme_grafana}
      GF_INSTALL_PLUGINS: ''
    volumes:
      - grafana-data:/var/lib/grafana
      - ./config/grafana/dashboards:/etc/grafana/provisioning/dashboards:ro
      - ./config/grafana/datasources:/etc/grafana/provisioning/datasources:ro
    ports:
      - "3001:3000"
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.51
    depends_on:
      - prometheus

  # ============================================================================
  # nginx Reverse Proxy (placeholder for Phase 8)
  # ============================================================================

  gogolatex-nginx:
    image: nginx:alpine
    container_name: gogolatex-nginx
    hostname: gogolatex-nginx
    restart: unless-stopped
    volumes:
      - ./config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./config/nginx/conf.d:/etc/nginx/conf.d:ro
    ports:
      - "80:80"
      - "443:443"
    networks:
      gogolatex-network:
        ipv4_address: 172.28.0.60
    depends_on:
      - gogolatex-keycloak
```

**Verification**:
```bash
cd latex-collaborative-editor
docker-compose config
```

---

## Task 3: Environment Variables (15 min)

### 3.1 Create .env File

Create: `gogotex-support-services/.env`

```env
# GoGoLaTeX Environment Variables for support stack
# Copy this file to .env inside gogotex-support-services and customize

# MongoDB
MONGODB_ROOT_PASSWORD=secure_mongodb_password_change_me
MONGODB_DATABASE=gogolatex
MONGODB_REPLICA_SET=gogolatex

# Redis
REDIS_PASSWORD=secure_redis_password_change_me

# MinIO
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=secure_minio_password_change_me

# Keycloak
KEYCLOAK_ADMIN_PASSWORD=secure_keycloak_admin_password
KEYCLOAK_DB_PASSWORD=secure_keycloak_db_password
KEYCLOAK_REALM=gogolatex
KEYCLOAK_CLIENT_ID=gogolatex-backend
KEYCLOAK_CLIENT_SECRET=your_client_secret_will_be_generated

# Grafana
GRAFANA_ADMIN_PASSWORD=secure_grafana_password

# Application
JWT_SECRET=your_jwt_secret_at_least_32_characters_long
API_BASE_URL=http://localhost:5000
FRONTEND_URL=http://localhost:3000

# SMTP (for emails)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=noreply@example.com
SMTP_PASSWORD=your_smtp_password
SMTP_FROM=noreply@example.com
SMTP_TLS=true

# Rate Limiting
RATE_LIMIT_API=1000
RATE_LIMIT_COMPILE=50
RATE_LIMIT_UPLOAD=100
```

### 3.2 Create .env.example

```bash
cp gogotex-support-services/.env gogotex-support-services/.env.example
# Replace all passwords with placeholders in .env.example
```

**Verification**:
```bash
cat latex-collaborative-editor/.env | grep PASSWORD
```

---

## Task 4: MongoDB Initialization Scripts (30 min)

### 4.1 MongoDB Initial Database Setup

Create: `latex-collaborative-editor/scripts/mongodb-init.js`

```javascript
// MongoDB Initialization Script for GoGoLaTeX
// This script runs on first container startup

// Switch to gogolatex database
db = db.getSiblingDB('gogolatex');

// Create users collection with indexes
db.createCollection('users');
db.users.createIndex({ 'oidcId': 1 }, { unique: true });
db.users.createIndex({ 'email': 1 }, { unique: true });
db.users.createIndex({ 'createdAt': 1 });

// Create projects collection with indexes
db.createCollection('projects');
db.projects.createIndex({ 'owner': 1 });
db.projects.createIndex({ 'collaborators.userId': 1 });
db.projects.createIndex({ 'createdAt': -1 });
db.projects.createIndex({ 'name': 'text' });

// Create documents collection with indexes
db.createCollection('documents');
db.documents.createIndex({ 'projectId': 1 });
db.documents.createIndex({ 'path': 1 });
db.documents.createIndex({ 'lastModifiedAt': -1 });

// Create sessions collection with TTL index
db.createCollection('sessions');
db.sessions.createIndex({ 'expiresAt': 1 }, { expireAfterSeconds: 0 });
db.sessions.createIndex({ 'userId': 1 });
db.sessions.createIndex({ 'token': 1 }, { unique: true });

// Create activity_logs collection with indexes
db.createCollection('activity_logs');
db.activity_logs.createIndex({ 'projectId': 1, 'timestamp': -1 });
db.activity_logs.createIndex({ 'userId': 1, 'timestamp': -1 });
db.activity_logs.createIndex({ 'timestamp': -1 });

print('✅ GoGoLaTeX database initialized successfully');
print('Collections created: users, projects, documents, sessions, activity_logs');
```

### 4.2 MongoDB Replica Set Initialization

Create: `latex-collaborative-editor/scripts/mongodb-replica-init.js`

```javascript
// MongoDB Replica Set Initialization Script
// This configures the 3-node replica set

rs.initiate({
  _id: "gogolatex",
  members: [
    { _id: 0, host: "gogolatex-mongodb-primary:27017", priority: 2 },
    { _id: 1, host: "gogolatex-mongodb-secondary-1:27017", priority: 1 },
    { _id: 2, host: "gogolatex-mongodb-secondary-2:27017", priority: 1 }
  ]
});

// Wait for replica set to stabilize
sleep(5000);

// Check status
print('✅ Replica set status:');
printjson(rs.status());
```

**Verification**:
```bash
# Will verify after containers start
```

---

## Task 5: Prometheus Configuration (20 min)

### 5.1 Prometheus Config

Create: `latex-collaborative-editor/config/prometheus/prometheus.yml`

```yaml
# Prometheus Configuration for GoGoLaTeX

global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'gogolatex'
    environment: 'development'

# Alerting configuration (optional)
alerting:
  alertmanagers:
    - static_configs:
        - targets: []

# Scrape configurations
scrape_configs:
  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # MongoDB exporter (add later)
  - job_name: 'mongodb'
    static_configs:
      - targets: []
    # TODO: Add mongodb-exporter container

  # Redis exporter (add later)
  - job_name: 'redis'
    static_configs:
      - targets: []
    # TODO: Add redis-exporter container

  # MinIO metrics
  - job_name: 'minio'
    metrics_path: /minio/v2/metrics/cluster
    static_configs:
      - targets: ['gogolatex-minio-1:9000']

  # Go services (add in Phase 2)
  - job_name: 'go-auth-service'
    static_configs:
      - targets: []
    # TODO: Add targets when services are ready

  - job_name: 'go-document-service'
    static_configs:
      - targets: []

  - job_name: 'go-compiler-service'
    static_configs:
      - targets: []

  # Node.js services (add in Phase 4)
  - job_name: 'node-realtime-server'
    static_configs:
      - targets: []

  - job_name: 'node-git-service'
    static_configs:
      - targets: []
```

**Verification**:
```bash
# Will verify after Prometheus starts
```

---

## Task 6: nginx Configuration (30 min)

### 6.1 Main nginx Config

Create: `latex-collaborative-editor/config/nginx/nginx.conf`

```nginx
# GoGoLaTeX nginx Configuration
# Main configuration file

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging format
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    # Performance settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss 
               application/rss+xml font/truetype font/opentype 
               application/vnd.ms-fontobject image/svg+xml;

    # Rate limiting zones
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/s;
    limit_req_zone $binary_remote_addr zone=auth_limit:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=compile_limit:10m rate=5r/s;

    # Include additional configurations
    include /etc/nginx/conf.d/*.conf;
}
```

### 6.2 Service Routing Config

Create: `latex-collaborative-editor/config/nginx/conf.d/gogolatex.conf`

```nginx
# GoGoLaTeX Service Routing Configuration

# Upstream definitions (will be populated as services are added)

upstream frontend {
    # Phase 3: Add frontend server
    # server gogolatex-frontend:3000;
    server 127.0.0.1:3000;  # Placeholder
}

upstream auth_service {
    # Phase 2: Add Go auth service
    # server gogolatex-go-auth:5001;
    server 127.0.0.1:5001;  # Placeholder
}

upstream document_service {
    # Phase 5: Add Go document service
    # server gogolatex-go-document:5002;
    server 127.0.0.1:5002;  # Placeholder
}

upstream compiler_service {
    # Phase 6: Add Go compiler service
    # server gogolatex-go-compiler:5003;
    server 127.0.0.1:5003;  # Placeholder
}

upstream realtime_server {
    # Phase 4: Add Node.js realtime server
    # server gogolatex-realtime-server:4000;
    server 127.0.0.1:4000;  # Placeholder
}

upstream keycloak {
    server gogolatex-keycloak:8080;
}

upstream minio {
    server gogolatex-minio-1:9000;
}

# Main server block
server {
    listen 80;
    server_name localhost;
    client_max_body_size 100M;

    # Frontend (React app)
    location / {
        proxy_pass http://frontend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Auth API
    location /api/auth/ {
        limit_req zone=auth_limit burst=20 nodelay;
        proxy_pass http://auth_service/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Document API
    location /api/documents/ {
        limit_req zone=api_limit burst=50 nodelay;
        proxy_pass http://document_service/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Compiler API
    location /api/compile/ {
        limit_req zone=compile_limit burst=10 nodelay;
        proxy_pass http://compiler_service/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;
    }

    # WebSocket (real-time collaboration)
    location /socket.io/ {
        proxy_pass http://realtime_server;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }

    # Keycloak (authentication)
    location /keycloak/ {
        proxy_pass http://keycloak/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }

    # MinIO (file storage - internal only)
    location /minio/ {
        # Only allow internal access
        allow 172.28.0.0/16;
        deny all;
        proxy_pass http://minio/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
```

**Verification**:
```bash
docker run --rm -v $(pwd)/config/nginx:/etc/nginx:ro nginx:alpine nginx -t
```

---

## Task 7: Start Infrastructure (30 min)

### 7.1 Start Services

```bash
cd latex-collaborative-editor

# Start infrastructure services only (no application services yet)
docker-compose up -d gogolatex-mongodb-primary gogolatex-mongodb-secondary-1 gogolatex-mongodb-secondary-2 gogolatex-mongodb-init

# Wait for MongoDB replica set
sleep 30

# Start Redis
docker-compose up -d gogolatex-redis-master gogolatex-redis-replica-1 gogolatex-redis-replica-2

# Start MinIO
docker-compose up -d gogolatex-minio-1 gogolatex-minio-2 gogolatex-minio-3 gogolatex-minio-4 gogolatex-minio-init

# Start Keycloak
docker-compose up -d gogolatex-keycloak-db gogolatex-keycloak

# Start monitoring
docker-compose up -d prometheus grafana

# Start nginx
docker-compose up -d gogolatex-nginx
```

### 7.2 Check Service Status

```bash
# Check all containers
docker-compose ps

# Check logs
docker-compose logs -f --tail=50
```

**Expected Output**: All services should be "Up" and healthy

---

## Task 8: Verify Infrastructure (45 min)

### 8.1 MongoDB Verification

```bash
# Connect to MongoDB primary
docker exec -it gogolatex-mongodb-primary mongosh -u admin -p changeme_mongodb_root --authenticationDatabase admin

# Inside mongosh:
rs.status()
show dbs
use gogolatex
show collections
exit
```

**Expected**: Replica set with 3 members, gogolatex database with collections

### 8.2 Redis Verification

```bash
# Test Redis master
docker exec -it gogolatex-redis-master redis-cli -a changeme_redis ping

# Check replication
docker exec -it gogolatex-redis-master redis-cli -a changeme_redis INFO replication

# Test set/get
docker exec -it gogolatex-redis-master redis-cli -a changeme_redis SET test "Hello GoGoLaTeX"
docker exec -it gogolatex-redis-master redis-cli -a changeme_redis GET test
```

**Expected**: PONG, replication info showing 2 replicas, value retrieval

### 8.3 MinIO Verification

```bash
# Access MinIO console
echo "MinIO Console: http://localhost:9001"
echo "Username: minioadmin"
echo "Password: changeme_minio"

# Check buckets via CLI
docker exec -it gogolatex-minio-1 mc ls local/
```

**Expected**: Web console accessible, buckets visible (projects, templates, backups, plugins)

### 8.4 Keycloak Verification

```bash
# Access Keycloak admin console
echo "Keycloak Admin: http://localhost:8080"
echo "Username: admin"
echo "Password: changeme_keycloak"

# Wait for Keycloak to be ready
docker exec -it gogolatex-keycloak curl -f http://localhost:8080/health/ready
```

**Expected**: Admin console accessible, health check returns 200

### 8.5 Prometheus Verification

```bash
# Access Prometheus UI
echo "Prometheus: http://localhost:9090"

# Check targets
curl -s http://localhost:9090/api/v1/targets | grep -o '"health":"[^"]*"'
```

**Expected**: UI accessible, targets listed (some may be down - that's expected)

### 8.6 Grafana Verification

```bash
# Access Grafana UI
echo "Grafana: http://localhost:3001"
echo "Username: admin"
echo "Password: changeme_grafana"
```

**Expected**: Login successful, empty dashboard (will add dashboards later)

### 8.7 nginx Verification

```bash
# Check nginx config
docker exec gogolatex-nginx nginx -t

# Test health endpoint
curl http://localhost/health
```

**Expected**: Config test passes, health returns "healthy"

---

## Task 9: Keycloak Realm Configuration (1 hour)

### 9.1 Create GoGoLaTeX Realm

You can perform the steps manually via the Keycloak admin console or run the provided helper script to automate realm, client, and test user creation.

1. Open Keycloak admin console (if exposed): http://localhost:8080
2. Or run the helper script (recommended):

```bash
# If Keycloak is exposed on host
KC_HOST=http://localhost:8080 ./scripts/keycloak-setup.sh
```

3. Login with admin credentials or let the script create the realm `gogolatex` and the test user for you.

### 9.2 Configure Realm Settings

1. Go to Realm Settings
2. **General Tab**:
   - User Profile Enabled: On
   - Email as Username: Off
   - Edit Username: Off
   - Forgot Password: On
   - Remember Me: On

3. **Login Tab**:
   - User Registration: On (for testing, disable in production)
   - Edit Username: Off
   - Forgot Password: On
   - Remember Me: On
   - Email as Username: Off

4. **Email Tab** (configure later in Phase 2):
   - From: noreply@gogolatex.local
   - Host: (SMTP host)
   - Port: 587

5. **Tokens Tab**:
   - Access Token Lifespan: 15 minutes
   - Refresh Token Max Reuse: 0
   - SSO Session Idle: 30 minutes
   - SSO Session Max: 10 hours

### 9.3 Create Client for Backend

1. Go to Clients → Create Client
2. **General Settings**:
   - Client ID: `gogolatex-backend`
   - Client Protocol: openid-connect
   - Client authentication: On
3. **Capability config**:
   - Standard flow: On
   - Direct access grants: On
4. **Login settings**:
   - Valid redirect URIs: `http://localhost:3000/*`, `http://localhost:5001/*`
   - Web Origins: `http://localhost:3000`, `http://localhost:5001`
5. Save and note the **Client Secret** from Credentials tab

### 9.4 Create Client Scopes

1. Go to Client Scopes → Create
2. Create scope: `gogolatex-api`
   - Protocol: openid-connect
   - Display on consent: Off
   - Include in token scope: On

### 9.5 Create Test User

1. Go to Users → Add User
2. **User Details**:
   - Username: `testuser`
   - Email: `testuser@gogolatex.local`
   - First Name: Test
   - Last Name: User
   - Email Verified: On
3. Save
4. Go to Credentials tab → Set Password:
   - Password: `Test123!`
   - Temporary: Off

**Verification**:
- Try logging in with test user at: http://localhost:8080/realms/gogolatex/account

---

## Task 10: Backup Scripts (30 min)

### 10.1 MongoDB Backup Script

Create: `latex-collaborative-editor/scripts/backup/backup-mongodb.sh`

```bash
#!/bin/bash
# MongoDB Backup Script for GoGoLaTeX
# Run daily via cron

set -e

BACKUP_DIR="/backups/mongodb"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MONGODB_URI="mongodb://admin:changeme_mongodb_root@gogolatex-mongodb-primary:27017/?replicaSet=gogolatex&authSource=admin"
MINIO_ALIAS="minio"
MINIO_BUCKET="backups"

echo "Starting MongoDB backup at $TIMESTAMP"

# Create backup
docker exec gogolatex-mongodb-primary mongodump \
  --uri="$MONGODB_URI" \
  --db=gogolatex \
  --gzip \
  --archive=/tmp/backup_${TIMESTAMP}.gz

# Copy to host
docker cp gogolatex-mongodb-primary:/tmp/backup_${TIMESTAMP}.gz /tmp/

# Upload to MinIO
docker exec gogolatex-minio-1 mc cp /tmp/backup_${TIMESTAMP}.gz ${MINIO_ALIAS}/${MINIO_BUCKET}/mongodb/backup_${TIMESTAMP}.gz

# Cleanup old backups (keep 30 days)
find /tmp/backup_*.gz -mtime +30 -delete

echo "✅ MongoDB backup completed: backup_${TIMESTAMP}.gz"
```

### 10.2 Redis Backup Script

Create: `latex-collaborative-editor/scripts/backup/backup-redis.sh`

```bash
#!/bin/bash
# Redis Backup Script for GoGoLaTeX
# Run daily via cron

set -e

BACKUP_DIR="/backups/redis"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MINIO_ALIAS="minio"
MINIO_BUCKET="backups"

echo "Starting Redis backup at $TIMESTAMP"

# Trigger Redis save
docker exec gogolatex-redis-master redis-cli -a changeme_redis BGSAVE

# Wait for save to complete
sleep 10

# Copy RDB file
docker cp gogolatex-redis-master:/data/dump.rdb /tmp/redis_backup_${TIMESTAMP}.rdb

# Upload to MinIO
docker exec gogolatex-minio-1 mc cp /tmp/redis_backup_${TIMESTAMP}.rdb ${MINIO_ALIAS}/${MINIO_BUCKET}/redis/redis_backup_${TIMESTAMP}.rdb

# Cleanup old backups (keep 7 days)
find /tmp/redis_backup_*.rdb -mtime +7 -delete

echo "✅ Redis backup completed: redis_backup_${TIMESTAMP}.rdb"
```

### 10.3 Make Scripts Executable

```bash
chmod +x latex-collaborative-editor/scripts/backup/*.sh
```

**Verification**:
```bash
# Test MongoDB backup
./latex-collaborative-editor/scripts/backup/backup-mongodb.sh

# Test Redis backup
./latex-collaborative-editor/scripts/backup/backup-redis.sh
```

---

## Task 11: Health Check Script (20 min)

### 11.1 Infrastructure Health Check

Create: `latex-collaborative-editor/scripts/health-check.sh`

```bash
#!/bin/bash
# GoGoLaTeX Infrastructure Health Check Script

set -e

echo "================================"
echo "GoGoLaTeX Health Check"
echo "================================"
echo ""

# Function to check service health
check_service() {
    local service_name=$1
    local check_command=$2
    
    echo -n "Checking $service_name... "
    if eval "$check_command" > /dev/null 2>&1; then
        echo "✅ OK"
        return 0
    else
        echo "❌ FAILED"
        return 1
    fi
}

# Check Docker
check_service "Docker" "docker ps"

# Check MongoDB
check_service "MongoDB Primary" "docker exec gogolatex-mongodb-primary mongosh --eval 'db.adminCommand(\"ping\")' --quiet"

# Check Redis
check_service "Redis Master" "docker exec gogolatex-redis-master redis-cli -a changeme_redis ping"

# Check MinIO
check_service "MinIO" "docker exec gogolatex-minio-1 mc ready local"

# Check Keycloak
check_service "Keycloak" "curl -sf http://localhost:8080/health/ready"

# Check Prometheus
check_service "Prometheus" "curl -sf http://localhost:9090/-/healthy"

# Check Grafana
check_service "Grafana" "curl -sf http://localhost:3001/api/health"

# Check nginx
check_service "nginx" "curl -sf http://localhost/health"

echo ""
echo "================================"
echo "Health check completed"
echo "================================"
```

```bash
chmod +x latex-collaborative-editor/scripts/health-check.sh
```

**Verification**:
```bash
./latex-collaborative-editor/scripts/health-check.sh
```

---

## Task 12: Documentation (30 min)

### 12.1 Infrastructure README

Create: `latex-collaborative-editor/README-INFRASTRUCTURE.md`

```markdown
# GoGoLaTeX Infrastructure

## Overview

This document describes the infrastructure setup for GoGoLaTeX.

## Services

### MongoDB (Replica Set)
- **Primary**: `gogolatex-mongodb-primary` (172.28.0.10:27017)
- **Secondary 1**: `gogolatex-mongodb-secondary-1` (172.28.0.11:27017)
- **Secondary 2**: `gogolatex-mongodb-secondary-2` (172.28.0.12:27017)
- **Replica Set**: `gogolatex`
- **Database**: `gogolatex`

**Connection String**:
```
mongodb://admin:PASSWORD@gogolatex-mongodb-primary:27017,gogolatex-mongodb-secondary-1:27017,gogolatex-mongodb-secondary-2:27017/gogolatex?replicaSet=gogolatex&authSource=admin
```

### Redis (Master-Replica)
- **Master**: `gogolatex-redis-master` (172.28.0.20:6379)
- **Replica 1**: `gogolatex-redis-replica-1` (172.28.0.21:6379)
- **Replica 2**: `gogolatex-redis-replica-2` (172.28.0.22:6379)

**Connection**: `redis://gogolatex-redis-master:6379` (password required)

### MinIO (Distributed)
- **Node 1**: `gogolatex-minio-1` (172.28.0.30:9000)
- **Node 2**: `gogolatex-minio-2` (172.28.0.31:9000)
- **Node 3**: `gogolatex-minio-3` (172.28.0.32:9000)
- **Node 4**: `gogolatex-minio-4` (172.28.0.33:9000)
- **Console**: http://localhost:9001

**Buckets**:
- `projects` - User project files
- `templates` - LaTeX templates
- `backups` - Database backups
- `plugins` - Plugin packages

### Keycloak
- **Server**: `gogolatex-keycloak` (172.28.0.40:8080)
- **Admin Console**: http://localhost:8080
- **Realm**: `gogolatex`
- **Client ID**: `gogolatex-backend`

### Monitoring
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3001

### nginx
- **Reverse Proxy**: http://localhost (172.28.0.60:80)

## Management Commands

### Start All Services
```bash
cd latex-collaborative-editor
docker-compose up -d
```

### Stop All Services
```bash
docker-compose down
```

### View Logs
```bash
docker-compose logs -f [service-name]
```

### Health Check
```bash
./scripts/health-check.sh
```

### Backups
```bash
# MongoDB
./scripts/backup/backup-mongodb.sh

# Redis
./scripts/backup/backup-redis.sh
```

## Troubleshooting

### MongoDB Replica Set Not Initializing
```bash
docker exec -it gogolatex-mongodb-primary mongosh -u admin -p changeme_mongodb_root --authenticationDatabase admin

# Inside mongosh:
rs.status()
rs.initiate()
```

### Redis Master-Replica Sync Issues
```bash
docker exec -it gogolatex-redis-master redis-cli -a changeme_redis INFO replication
```

### MinIO Distributed Mode Issues
```bash
docker logs gogolatex-minio-1
```

### Keycloak Startup Slow
Wait 2-3 minutes for first startup (database initialization)

## Security Notes

- Change all default passwords in `.env`
- Use SSL/TLS in production (nginx configuration)
- Restrict MinIO bucket access
- Configure Keycloak properly for production
```

---

## Phase 1 Completion Checklist

### Infrastructure
- [ ] All Docker services running
- [ ] MongoDB replica set initialized (3 nodes)
- [ ] Redis master-replica working (1 master + 2 replicas)
- [ ] MinIO distributed mode active (4 nodes)
- [ ] All MinIO buckets created (projects, templates, backups, plugins)
- [ ] Keycloak running and accessible
- [ ] Keycloak realm "gogolatex" created
- [ ] Keycloak client "gogolatex-backend" configured
- [ ] Test user created in Keycloak
- [ ] Prometheus running and scraping targets
- [ ] Grafana running (dashboards to be added later)
- [ ] nginx reverse proxy configured

### Scripts & Configuration
- [ ] Environment variables configured (`.env`)
- [ ] MongoDB initialization script working
- [ ] Backup scripts created and tested
- [ ] Health check script working
- [ ] nginx configuration valid

### Verification
- [ ] `docker-compose ps` shows all services as "Up"
- [ ] `./scripts/health-check.sh` all checks pass
- [ ] MongoDB: Can connect and see gogolatex database
- [ ] Redis: Can SET and GET values
- [ ] MinIO: Console accessible, buckets visible
- [ ] Keycloak: Admin console accessible, test user can login
- [ ] Prometheus: Targets visible (some down is OK)
- [ ] Grafana: Dashboard accessible
- [ ] nginx: Health endpoint returns "healthy"

### Documentation
- [ ] README-INFRASTRUCTURE.md created
- [ ] All passwords documented in `.env.example`
- [ ] Connection strings documented

---

## Next Phase

**Phase 2**: Go Authentication Service

Once all checklist items are complete, proceed to `PHASE-02-go-auth-service.md`

---

## Estimated Time

- **Minimum**: 3 hours (if everything works perfectly)
- **Expected**: 5-8 hours (troubleshooting included)
- **Maximum**: 1-2 days (significant issues)

## Common Issues

1. **Port conflicts**: Check if ports 27017, 6379, 9000, 8080 are already in use
2. **Resource limits**: Ensure Docker has enough memory (8GB recommended)
3. **Replica set delays**: MongoDB replica initialization can take 1-2 minutes
4. **Keycloak slow start**: First start takes 2-3 minutes for database setup
