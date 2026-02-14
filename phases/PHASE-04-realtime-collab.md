# Phase 4: Real-time Collaboration (Node.js + Yjs)

**Duration**: 4-5 days  
**Goal**: Implement real-time collaborative editing with Yjs and WebSocket synchronization

**Prerequisites**: Phase 3 completed, frontend and auth service running

---

## Prerequisites

- [ ] Phase 3 frontend completed and running
- [ ] Auth service operational
- [ ] Redis running and accessible
- [ ] Node.js 20+ installed
- [ ] Basic understanding of WebSocket and CRDT concepts

---

## Task 1: Node.js Project Setup (45 min)

### 1.1 Initialize Node.js Project

```bash
cd latex-collaborative-editor/backend/node-services
mkdir realtime-server
cd realtime-server

# Initialize package.json
npm init -y

# Update package.json name and version
```

### 1.2 Install Dependencies

```bash
# Core dependencies
npm install express socket.io yjs y-protocols lib0

# Redis for pub/sub and persistence
npm install ioredis redis

# TypeScript and type definitions
npm install --save-dev typescript @types/node @types/express ts-node nodemon

# Environment configuration
npm install dotenv

# Logging
npm install winston

# CORS
npm install cors @types/cors

# JWT validation
npm install jsonwebtoken @types/jsonwebtoken

# Utility
npm install uuid @types/uuid
```

### 1.3 TypeScript Configuration

Create: `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "moduleResolution": "node",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

### 1.4 Package.json Scripts

Update `package.json`:

```json
{
  "name": "gogotex-realtime-server",
  "version": "1.0.0",
  "description": "Real-time collaboration server for gogotex",
  "main": "dist/server.js",
  "scripts": {
    "build": "tsc",
    "start": "node dist/server.js",
    "dev": "nodemon --exec ts-node src/server.ts",
    "clean": "rm -rf dist",
    "type-check": "tsc --noEmit"
  },
  "keywords": ["latex", "collaboration", "yjs", "websocket"],
  "author": "",
  "license": "MIT"
}
```

### 1.5 Create Directory Structure

```bash
mkdir -p src/{config,services,models,utils,middleware}
```

**Verification**:
```bash
npm run type-check
```

---

## Task 2: Configuration (30 min)

### 2.1 Configuration Module

Create: `src/config/config.ts`

```typescript
import dotenv from 'dotenv';
import path from 'path';

// Load .env file
dotenv.config({ path: path.join(__dirname, '../../../.env') });

export interface Config {
  server: {
    port: number;
    host: string;
    environment: string;
  };
  redis: {
    host: string;
    port: number;
    password: string;
    db: number;
  };
  auth: {
    jwtSecret: string;
  };
  yjs: {
    gcEnabled: boolean;
    persistenceInterval: number; // milliseconds
    inactiveTimeout: number; // milliseconds
  };
}

export const config: Config = {
  server: {
    port: parseInt(process.env.REALTIME_PORT || '4000', 10),
    host: process.env.REALTIME_HOST || '0.0.0.0',
    environment: process.env.SERVER_ENVIRONMENT || 'development',
  },
  redis: {
    host: process.env.REDIS_HOST || 'gogotex-redis-master',
    port: parseInt(process.env.REDIS_PORT || '6379', 10),
    password: process.env.REDIS_PASSWORD || '',
    db: 0,
  },
  auth: {
    jwtSecret: process.env.JWT_SECRET || '',
  },
  yjs: {
    gcEnabled: true,
    persistenceInterval: 5000, // Save to Redis every 5 seconds
    inactiveTimeout: 900000, // 15 minutes
  },
};

// Validate required config
if (!config.auth.jwtSecret) {
  throw new Error('JWT_SECRET is required');
}

if (!config.redis.password) {
  throw new Error('REDIS_PASSWORD is required');
}
```

### 2.2 Update .env File

Add to `latex-collaborative-editor/.env`:

```env
# Realtime Server
REALTIME_PORT=4000
REALTIME_HOST=0.0.0.0

# Already exists from Phase 2
# REDIS_HOST=gogotex-redis-master
# REDIS_PORT=6379
# REDIS_PASSWORD=changeme_redis
# JWT_SECRET=your_super_secret_jwt_key_at_least_32_characters_long_please_change_this
```

**Verification**:
```bash
npm run type-check
```

---

## Task 3: Logger Setup (20 min)

Create: `src/utils/logger.ts`

```typescript
import winston from 'winston';
import { config } from '../config/config';

const logFormat = winston.format.combine(
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  winston.format.errors({ stack: true }),
  winston.format.splat(),
  winston.format.json()
);

const consoleFormat = winston.format.combine(
  winston.format.colorize(),
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  winston.format.printf(({ timestamp, level, message, ...meta }) => {
    return `${timestamp} [${level}]: ${message} ${
      Object.keys(meta).length ? JSON.stringify(meta, null, 2) : ''
    }`;
  })
);

export const logger = winston.createLogger({
  level: config.server.environment === 'production' ? 'info' : 'debug',
  format: logFormat,
  transports: [
    new winston.transports.Console({
      format: config.server.environment === 'production' ? logFormat : consoleFormat,
    }),
  ],
});
```

---

## Task 4: Redis Client (30 min)

Create: `src/services/redis.ts`

```typescript
import Redis from 'ioredis';
import { config } from '../config/config';
import { logger } from '../utils/logger';

export class RedisService {
  private client: Redis;
  private pubClient: Redis;
  private subClient: Redis;

  constructor() {
    const redisConfig = {
      host: config.redis.host,
      port: config.redis.port,
      password: config.redis.password,
      db: config.redis.db,
      retryStrategy: (times: number) => {
        const delay = Math.min(times * 50, 2000);
        return delay;
      },
    };

    // Main client for get/set operations
    this.client = new Redis(redisConfig);

    // Pub/Sub clients (separate connections required)
    this.pubClient = new Redis(redisConfig);
    this.subClient = new Redis(redisConfig);

    this.setupEventHandlers();
  }

  private setupEventHandlers() {
    this.client.on('connect', () => {
      logger.info('Redis main client connected');
    });

    this.client.on('error', (err) => {
      logger.error('Redis main client error:', err);
    });

    this.pubClient.on('connect', () => {
      logger.info('Redis pub client connected');
    });

    this.subClient.on('connect', () => {
      logger.info('Redis sub client connected');
    });
  }

  // Get Yjs document updates from Redis
  async getYjsUpdates(documentId: string): Promise<Buffer[]> {
    const key = `yjs:document:${documentId}:updates`;
    const updates = await this.client.lrange(key, 0, -1);
    return updates.map((update) => Buffer.from(update, 'base64'));
  }

  // Append Yjs update to Redis
  async appendYjsUpdate(documentId: string, update: Uint8Array): Promise<void> {
    const key = `yjs:document:${documentId}:updates`;
    const base64Update = Buffer.from(update).toString('base64');
    await this.client.rpush(key, base64Update);
    
    // Set TTL (7 days)
    await this.client.expire(key, 7 * 24 * 60 * 60);
  }

  // Store Yjs state snapshot
  async storeYjsState(documentId: string, state: Uint8Array): Promise<void> {
    const key = `yjs:document:${documentId}:state`;
    const base64State = Buffer.from(state).toString('base64');
    await this.client.setex(key, 7 * 24 * 60 * 60, base64State);
  }

  // Get Yjs state snapshot
  async getYjsState(documentId: string): Promise<Buffer | null> {
    const key = `yjs:document:${documentId}:state`;
    const state = await this.client.get(key);
    return state ? Buffer.from(state, 'base64') : null;
  }

  // Publish message to channel
  async publish(channel: string, message: string): Promise<void> {
    await this.pubClient.publish(channel, message);
  }

  // Subscribe to channel
  subscribe(channel: string, callback: (message: string) => void): void {
    this.subClient.subscribe(channel);
    this.subClient.on('message', (ch, msg) => {
      if (ch === channel) {
        callback(msg);
      }
    });
  }

  // Add user to active users set
  async addActiveUser(documentId: string, userId: string): Promise<void> {
    const key = `yjs:document:${documentId}:active`;
    await this.client.sadd(key, userId);
    await this.client.expire(key, 7 * 24 * 60 * 60);
  }

  // Remove user from active users set
  async removeActiveUser(documentId: string, userId: string): Promise<void> {
    const key = `yjs:document:${documentId}:active`;
    await this.client.srem(key, userId);
  }

  // Get active users
  async getActiveUsers(documentId: string): Promise<string[]> {
    const key = `yjs:document:${documentId}:active`;
    return await this.client.smembers(key);
  }

  // Update last save timestamp
  async updateLastSave(documentId: string): Promise<void> {
    const key = `yjs:document:${documentId}:lastSave`;
    await this.client.set(key, Date.now().toString());
    await this.client.expire(key, 7 * 24 * 60 * 60);
  }

  // Close all connections
  async close(): Promise<void> {
    await this.client.quit();
    await this.pubClient.quit();
    await this.subClient.quit();
    logger.info('Redis connections closed');
  }
}
```

**Verification**:
```bash
npm run type-check
```

---

## Task 5: Yjs Document Manager (2 hours)

Create: `src/services/yjs-manager.ts`

```typescript
import * as Y from 'yjs';
import * as awarenessProtocol from 'y-protocols/awareness';
import * as syncProtocol from 'y-protocols/sync';
import { encoding, decoding } from 'lib0';
import { RedisService } from './redis';
import { logger } from '../utils/logger';
import { config } from '../config/config';

export interface DocumentInfo {
  documentId: string;
  yjsDoc: Y.Doc;
  awareness: awarenessProtocol.Awareness;
  connections: Map<string, any>; // socketId -> connection info
  lastAccess: number;
  persistenceTimer?: NodeJS.Timer;
}

export class YjsDocumentManager {
  private documents: Map<string, DocumentInfo>;
  private redis: RedisService;

  constructor(redis: RedisService) {
    this.documents = new Map();
    this.redis = redis;

    // Cleanup inactive documents every 5 minutes
    setInterval(() => this.cleanupInactiveDocuments(), 5 * 60 * 1000);

    logger.info('Yjs Document Manager initialized');
  }

  // Get or create document
  async getDocument(documentId: string): Promise<DocumentInfo> {
    let docInfo = this.documents.get(documentId);

    if (!docInfo) {
      // Create new Yjs document
      const yjsDoc = new Y.Doc();
      const awareness = new awarenessProtocol.Awareness(yjsDoc);

      // Load persisted state from Redis
      await this.loadFromRedis(documentId, yjsDoc);

      // Setup update listener for persistence
      yjsDoc.on('update', (update: Uint8Array, origin: any) => {
        if (origin !== 'redis-load') {
          this.persistUpdate(documentId, update);
        }
      });

      docInfo = {
        documentId,
        yjsDoc,
        awareness,
        connections: new Map(),
        lastAccess: Date.now(),
      };

      // Setup periodic persistence
      docInfo.persistenceTimer = setInterval(() => {
        this.persistState(documentId);
      }, config.yjs.persistenceInterval);

      this.documents.set(documentId, docInfo);
      logger.info('Created new Yjs document', { documentId });
    }

    docInfo.lastAccess = Date.now();
    return docInfo;
  }

  // Load document state from Redis
  private async loadFromRedis(documentId: string, yjsDoc: Y.Doc): Promise<void> {
    try {
      // Try to load state snapshot first
      const state = await this.redis.getYjsState(documentId);
      if (state) {
        Y.applyUpdate(yjsDoc, new Uint8Array(state), 'redis-load');
        logger.debug('Loaded Yjs state from Redis', { documentId });
        return;
      }

      // Fall back to loading updates
      const updates = await this.redis.getYjsUpdates(documentId);
      if (updates.length > 0) {
        for (const update of updates) {
          Y.applyUpdate(yjsDoc, new Uint8Array(update), 'redis-load');
        }
        logger.debug('Loaded Yjs updates from Redis', { 
          documentId, 
          updateCount: updates.length 
        });
      } else {
        logger.debug('No persisted data found for document', { documentId });
      }
    } catch (error) {
      logger.error('Failed to load document from Redis', { documentId, error });
    }
  }

  // Persist update to Redis
  private async persistUpdate(documentId: string, update: Uint8Array): Promise<void> {
    try {
      await this.redis.appendYjsUpdate(documentId, update);
      logger.debug('Persisted Yjs update to Redis', { 
        documentId, 
        size: update.length 
      });
    } catch (error) {
      logger.error('Failed to persist update', { documentId, error });
    }
  }

  // Persist full state snapshot to Redis
  private async persistState(documentId: string): Promise<void> {
    const docInfo = this.documents.get(documentId);
    if (!docInfo) return;

    try {
      const state = Y.encodeStateAsUpdate(docInfo.yjsDoc);
      await this.redis.storeYjsState(documentId, state);
      await this.redis.updateLastSave(documentId);
      logger.debug('Persisted Yjs state snapshot', { 
        documentId, 
        size: state.length 
      });
    } catch (error) {
      logger.error('Failed to persist state', { documentId, error });
    }
  }

  // Add connection to document
  addConnection(documentId: string, socketId: string, userId: string): void {
    const docInfo = this.documents.get(documentId);
    if (!docInfo) return;

    docInfo.connections.set(socketId, { userId, connectedAt: Date.now() });
    this.redis.addActiveUser(documentId, userId);

    logger.debug('Added connection to document', { 
      documentId, 
      socketId, 
      userId,
      totalConnections: docInfo.connections.size 
    });
  }

  // Remove connection from document
  async removeConnection(documentId: string, socketId: string): Promise<void> {
    const docInfo = this.documents.get(documentId);
    if (!docInfo) return;

    const connection = docInfo.connections.get(socketId);
    docInfo.connections.delete(socketId);

    if (connection) {
      await this.redis.removeActiveUser(documentId, connection.userId);
    }

    logger.debug('Removed connection from document', { 
      documentId, 
      socketId,
      remainingConnections: docInfo.connections.size 
    });

    // If no more connections, persist and schedule cleanup
    if (docInfo.connections.size === 0) {
      await this.persistState(documentId);
    }
  }

  // Get document info
  getDocumentInfo(documentId: string): DocumentInfo | undefined {
    return this.documents.get(documentId);
  }

  // Cleanup inactive documents
  private cleanupInactiveDocuments(): void {
    const now = Date.now();
    const timeout = config.yjs.inactiveTimeout;

    for (const [documentId, docInfo] of this.documents.entries()) {
      if (docInfo.connections.size === 0 && now - docInfo.lastAccess > timeout) {
        logger.info('Cleaning up inactive document', { documentId });
        
        // Clear persistence timer
        if (docInfo.persistenceTimer) {
          clearInterval(docInfo.persistenceTimer);
        }

        // Destroy Yjs document
        docInfo.yjsDoc.destroy();
        this.documents.delete(documentId);
      }
    }
  }

  // Get active documents count
  getActiveDocumentsCount(): number {
    return this.documents.size;
  }

  // Get total connections count
  getTotalConnectionsCount(): number {
    let total = 0;
    for (const docInfo of this.documents.values()) {
      total += docInfo.connections.size;
    }
    return total;
  }
}
```

**Verification**:
```bash
npm run type-check
```

---

## Task 6: Authentication Middleware (30 min)

Create: `src/middleware/auth.ts`

```typescript
import jwt from 'jsonwebtoken';
import { Socket } from 'socket.io';
import { config } from '../config/config';
import { logger } from '../utils/logger';

export interface AuthenticatedSocket extends Socket {
  userId?: string;
  email?: string;
  name?: string;
}

export interface JWTPayload {
  userId: string;
  email: string;
  name: string;
  iat: number;
  exp: number;
}

export const authenticateSocket = async (
  socket: AuthenticatedSocket,
  next: (err?: Error) => void
): Promise<void> => {
  try {
    // Get token from handshake auth or query
    const token = 
      socket.handshake.auth.token || 
      socket.handshake.query.token as string;

    if (!token) {
      logger.warn('Socket connection attempted without token', {
        socketId: socket.id,
      });
      return next(new Error('Authentication token required'));
    }

    // Verify JWT token
    const decoded = jwt.verify(token, config.auth.jwtSecret) as JWTPayload;

    // Attach user info to socket
    socket.userId = decoded.userId;
    socket.email = decoded.email;
    socket.name = decoded.name;

    logger.debug('Socket authenticated successfully', {
      socketId: socket.id,
      userId: decoded.userId,
      email: decoded.email,
    });

    next();
  } catch (error) {
    logger.error('Socket authentication failed', {
      socketId: socket.id,
      error: error instanceof Error ? error.message : 'Unknown error',
    });
    next(new Error('Invalid or expired token'));
  }
};
```

**Verification**:
```bash
npm run type-check
```

---

## Task 7: WebSocket Collaboration Handler (2 hours)

Create: `src/services/collaboration.ts`

```typescript
import { Server as SocketIOServer, Socket } from 'socket.io';
import * as Y from 'yjs';
import * as awarenessProtocol from 'y-protocols/awareness';
import * as syncProtocol from 'y-protocols/sync';
import { encoding, decoding } from 'lib0';
import { YjsDocumentManager } from './yjs-manager';
import { RedisService } from './redis';
import { AuthenticatedSocket } from '../middleware/auth';
import { logger } from '../utils/logger';

export class CollaborationService {
  private io: SocketIOServer;
  private yjsManager: YjsDocumentManager;
  private redis: RedisService;

  constructor(io: SocketIOServer, redis: RedisService) {
    this.io = io;
    this.redis = redis;
    this.yjsManager = new YjsDocumentManager(redis);

    this.setupSocketHandlers();
    this.setupRedisSubscription();

    logger.info('Collaboration service initialized');
  }

  private setupSocketHandlers(): void {
    this.io.on('connection', (socket: AuthenticatedSocket) => {
      logger.info('Client connected', {
        socketId: socket.id,
        userId: socket.userId,
        email: socket.email,
      });

      // Handle document join
      socket.on('join-document', async (data: { documentId: string }) => {
        await this.handleJoinDocument(socket, data.documentId);
      });

      // Handle Yjs sync messages
      socket.on('yjs-sync', async (data: { documentId: string; update: Uint8Array }) => {
        await this.handleYjsSync(socket, data.documentId, data.update);
      });

      // Handle awareness updates (cursor positions, selections)
      socket.on('awareness-update', async (data: { documentId: string; update: Uint8Array }) => {
        await this.handleAwarenessUpdate(socket, data.documentId, data.update);
      });

      // Handle leave document
      socket.on('leave-document', async (data: { documentId: string }) => {
        await this.handleLeaveDocument(socket, data.documentId);
      });

      // Handle disconnect
      socket.on('disconnect', () => {
        this.handleDisconnect(socket);
      });

      // Send initial stats
      this.sendStats(socket);
    });
  }

  private async handleJoinDocument(
    socket: AuthenticatedSocket,
    documentId: string
  ): Promise<void> {
    try {
      logger.info('Client joining document', {
        socketId: socket.id,
        userId: socket.userId,
        documentId,
      });

      // Join socket.io room
      socket.join(`document:${documentId}`);

      // Get or create document
      const docInfo = await this.yjsManager.getDocument(documentId);

      // Add connection
      this.yjsManager.addConnection(documentId, socket.id, socket.userId!);

      // Send current document state to client
      const stateVector = Y.encodeStateAsUpdate(docInfo.yjsDoc);
      socket.emit('yjs-sync', {
        documentId,
        update: Buffer.from(stateVector).toString('base64'),
      });

      // Send current awareness state
      const awarenessUpdate = awarenessProtocol.encodeAwarenessUpdate(
        docInfo.awareness,
        Array.from(docInfo.awareness.getStates().keys())
      );
      socket.emit('awareness-update', {
        documentId,
        update: Buffer.from(awarenessUpdate).toString('base64'),
      });

      // Get active users
      const activeUsers = await this.redis.getActiveUsers(documentId);

      // Notify other users
      socket.to(`document:${documentId}`).emit('user-joined', {
        documentId,
        userId: socket.userId,
        name: socket.name,
        email: socket.email,
        activeUsers,
      });

      // Confirm join to client
      socket.emit('joined-document', {
        documentId,
        activeUsers,
        connectionCount: docInfo.connections.size,
      });

      logger.debug('Client joined document successfully', {
        socketId: socket.id,
        documentId,
        activeUsers: activeUsers.length,
      });
    } catch (error) {
      logger.error('Failed to join document', {
        socketId: socket.id,
        documentId,
        error,
      });
      socket.emit('error', {
        message: 'Failed to join document',
        documentId,
      });
    }
  }

  private async handleYjsSync(
    socket: AuthenticatedSocket,
    documentId: string,
    updateData: any
  ): Promise<void> {
    try {
      // Decode update (handle both Buffer and base64 string)
      const update = typeof updateData === 'string' 
        ? Buffer.from(updateData, 'base64')
        : Buffer.from(updateData);

      const docInfo = this.yjsManager.getDocumentInfo(documentId);
      if (!docInfo) {
        throw new Error('Document not found');
      }

      // Apply update to Yjs document
      Y.applyUpdate(docInfo.yjsDoc, new Uint8Array(update), socket.id);

      // Broadcast update to other clients in the same document
      socket.to(`document:${documentId}`).emit('yjs-sync', {
        documentId,
        update: update.toString('base64'),
        fromUserId: socket.userId,
      });

      // Publish to Redis for other server instances
      await this.redis.publish(`yjs:${documentId}`, JSON.stringify({
        type: 'sync',
        update: update.toString('base64'),
        fromSocketId: socket.id,
        fromUserId: socket.userId,
      }));

      logger.debug('Yjs sync processed', {
        documentId,
        socketId: socket.id,
        updateSize: update.length,
      });
    } catch (error) {
      logger.error('Failed to process Yjs sync', {
        socketId: socket.id,
        documentId,
        error,
      });
    }
  }

  private async handleAwarenessUpdate(
    socket: AuthenticatedSocket,
    documentId: string,
    updateData: any
  ): Promise<void> {
    try {
      // Decode update
      const update = typeof updateData === 'string'
        ? Buffer.from(updateData, 'base64')
        : Buffer.from(updateData);

      const docInfo = this.yjsManager.getDocumentInfo(documentId);
      if (!docInfo) {
        throw new Error('Document not found');
      }

      // Apply awareness update
      awarenessProtocol.applyAwarenessUpdate(
        docInfo.awareness,
        new Uint8Array(update),
        socket.id
      );

      // Broadcast to other clients
      socket.to(`document:${documentId}`).emit('awareness-update', {
        documentId,
        update: update.toString('base64'),
        fromUserId: socket.userId,
      });

      // Publish to Redis
      await this.redis.publish(`yjs:${documentId}`, JSON.stringify({
        type: 'awareness',
        update: update.toString('base64'),
        fromSocketId: socket.id,
        fromUserId: socket.userId,
      }));

      logger.debug('Awareness update processed', {
        documentId,
        socketId: socket.id,
      });
    } catch (error) {
      logger.error('Failed to process awareness update', {
        socketId: socket.id,
        documentId,
        error,
      });
    }
  }

  private async handleLeaveDocument(
    socket: AuthenticatedSocket,
    documentId: string
  ): Promise<void> {
    try {
      logger.info('Client leaving document', {
        socketId: socket.id,
        userId: socket.userId,
        documentId,
      });

      // Leave socket.io room
      socket.leave(`document:${documentId}`);

      // Remove connection
      await this.yjsManager.removeConnection(documentId, socket.id);

      // Notify other users
      socket.to(`document:${documentId}`).emit('user-left', {
        documentId,
        userId: socket.userId,
      });
    } catch (error) {
      logger.error('Failed to leave document', {
        socketId: socket.id,
        documentId,
        error,
      });
    }
  }

  private handleDisconnect(socket: AuthenticatedSocket): void {
    logger.info('Client disconnected', {
      socketId: socket.id,
      userId: socket.userId,
    });

    // Client will be automatically removed from all rooms
    // Cleanup will happen via the document manager
  }

  private setupRedisSubscription(): void {
    // Subscribe to all Yjs channels
    this.redis.subscribe('yjs:*', (message: string) => {
      try {
        const data = JSON.parse(message);
        const { type, documentId, update, fromSocketId, fromUserId } = data;

        // Skip if from same server instance
        if (fromSocketId && this.io.sockets.sockets.has(fromSocketId)) {
          return;
        }

        // Broadcast to clients in this server instance
        if (type === 'sync') {
          this.io.to(`document:${documentId}`).emit('yjs-sync', {
            documentId,
            update,
            fromUserId,
          });
        } else if (type === 'awareness') {
          this.io.to(`document:${documentId}`).emit('awareness-update', {
            documentId,
            update,
            fromUserId,
          });
        }
      } catch (error) {
        logger.error('Failed to process Redis message', { error });
      }
    });
  }

  private sendStats(socket: Socket): void {
    socket.emit('stats', {
      activeDocuments: this.yjsManager.getActiveDocumentsCount(),
      totalConnections: this.yjsManager.getTotalConnectionsCount(),
    });
  }

  // Get statistics
  getStats() {
    return {
      activeDocuments: this.yjsManager.getActiveDocumentsCount(),
      totalConnections: this.yjsManager.getTotalConnectionsCount(),
    };
  }
}
```

**Verification**:
```bash
npm run type-check
```

---

## Task 8: Main Server (1 hour)

Create: `src/server.ts`

```typescript
import express from 'express';
import { createServer } from 'http';
import { Server as SocketIOServer } from 'socket.io';
import cors from 'cors';
import { config } from './config/config';
import { logger } from './utils/logger';
import { RedisService } from './services/redis';
import { CollaborationService } from './services/collaboration';
import { authenticateSocket } from './middleware/auth';

// Create Express app
const app = express();
const httpServer = createServer(app);

// CORS configuration
app.use(cors({
  origin: process.env.FRONTEND_URL || 'http://localhost:3000',
  credentials: true,
}));

app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'realtime-server',
    timestamp: Date.now(),
  });
});

// Stats endpoint
app.get('/stats', (req, res) => {
  if (collaborationService) {
    res.json(collaborationService.getStats());
  } else {
    res.status(503).json({ error: 'Service not ready' });
  }
});

// Socket.IO setup
const io = new SocketIOServer(httpServer, {
  cors: {
    origin: process.env.FRONTEND_URL || 'http://localhost:3000',
    credentials: true,
  },
  pingTimeout: 60000,
  pingInterval: 25000,
  transports: ['websocket', 'polling'],
});

// Apply authentication middleware
io.use(authenticateSocket);

// Initialize services
let redis: RedisService;
let collaborationService: CollaborationService;

async function startServer() {
  try {
    logger.info('Starting gogotex Realtime Server', {
      environment: config.server.environment,
      port: config.server.port,
    });

    // Initialize Redis
    redis = new RedisService();
    logger.info('Redis service initialized');

    // Initialize collaboration service
    collaborationService = new CollaborationService(io, redis);
    logger.info('Collaboration service initialized');

    // Start HTTP server
    httpServer.listen(config.server.port, config.server.host, () => {
      logger.info('Realtime server started', {
        host: config.server.host,
        port: config.server.port,
        url: `http://${config.server.host}:${config.server.port}`,
      });
    });

    // Log stats every minute
    setInterval(() => {
      const stats = collaborationService.getStats();
      logger.info('Server stats', stats);
    }, 60000);

  } catch (error) {
    logger.error('Failed to start server', { error });
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGINT', async () => {
  logger.info('Received SIGINT, shutting down gracefully...');
  
  if (redis) {
    await redis.close();
  }
  
  httpServer.close(() => {
    logger.info('Server closed');
    process.exit(0);
  });
});

process.on('SIGTERM', async () => {
  logger.info('Received SIGTERM, shutting down gracefully...');
  
  if (redis) {
    await redis.close();
  }
  
  httpServer.close(() => {
    logger.info('Server closed');
    process.exit(0);
  });
});

// Start the server
startServer();
```

**Verification**:
```bash
npm run dev
# Should start without errors
```

---

## Task 9: Frontend Integration (2 hours)

### 9.1 Install Frontend Dependencies

```bash
cd latex-collaborative-editor/frontend

npm install yjs y-codemirror.next socket.io-client y-protocols
```

### 9.2 Create WebSocket Service

Create: `frontend/src/services/websocket.ts`

```typescript
import { io, Socket } from 'socket.io-client';
import { useAuthStore } from '../stores/authStore';

const WS_URL = import.meta.env.VITE_WS_URL || 'http://localhost:4000';

class WebSocketService {
  private socket: Socket | null = null;
  private documentId: string | null = null;

  connect(): Promise<Socket> {
    return new Promise((resolve, reject) => {
      const token = useAuthStore.getState().accessToken;
      
      if (!token) {
        reject(new Error('No authentication token'));
        return;
      }

      this.socket = io(WS_URL, {
        auth: { token },
        transports: ['websocket', 'polling'],
      });

      this.socket.on('connect', () => {
        console.log('WebSocket connected', this.socket?.id);
        resolve(this.socket!);
      });

      this.socket.on('connect_error', (error) => {
        console.error('WebSocket connection error:', error);
        reject(error);
      });

      this.socket.on('error', (error) => {
        console.error('WebSocket error:', error);
      });

      this.socket.on('disconnect', (reason) => {
        console.log('WebSocket disconnected:', reason);
      });
    });
  }

  joinDocument(documentId: string): void {
    if (!this.socket) {
      throw new Error('Socket not connected');
    }

    this.documentId = documentId;
    this.socket.emit('join-document', { documentId });
  }

  leaveDocument(documentId: string): void {
    if (!this.socket) return;
    
    this.socket.emit('leave-document', { documentId });
    this.documentId = null;
  }

  getSocket(): Socket | null {
    return this.socket;
  }

  disconnect(): void {
    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
    }
  }
}

export const websocketService = new WebSocketService();
```

### 9.3 Create Collaborative Editor Component

Create: `frontend/src/components/CollaborativeEditor.tsx`

```typescript
import { useEffect, useRef, useState } from 'react';
import { EditorView, basicSetup } from 'codemirror';
import { EditorState } from '@codemirror/state';
import { StreamLanguage } from '@codemirror/language';
import { stex } from '@codemirror/legacy-modes/mode/stex';
import * as Y from 'yjs';
import { yCollab } from 'y-codemirror.next';
import { WebsocketProvider } from 'y-websocket'; // Alternative: use socket.io directly
import { websocketService } from '../services/websocket';

interface CollaborativeEditorProps {
  documentId: string;
  initialContent?: string;
}

export function CollaborativeEditor({ documentId, initialContent = '' }: CollaborativeEditorProps) {
  const editorRef = useRef<HTMLDivElement>(null);
  const viewRef = useRef<EditorView | null>(null);
  const yjsDocRef = useRef<Y.Doc | null>(null);
  const [activeUsers, setActiveUsers] = useState<string[]>([]);

  useEffect(() => {
    if (!editorRef.current) return;

    // Create Yjs document
    const yjsDoc = new Y.Doc();
    yjsDocRef.current = yjsDoc;

    // Get the shared text type
    const ytext = yjsDoc.getText('codemirror');

    // Connect to WebSocket
    websocketService.connect().then((socket) => {
      // Join document room
      websocketService.joinDocument(documentId);

      // Listen for sync messages
      socket.on('yjs-sync', (data: { documentId: string; update: string }) => {
        if (data.documentId === documentId) {
          const update = Buffer.from(data.update, 'base64');
          Y.applyUpdate(yjsDoc, new Uint8Array(update));
        }
      });

      // Listen for awareness updates
      socket.on('awareness-update', (data: { documentId: string; update: string }) => {
        if (data.documentId === documentId) {
          // TODO: Apply awareness update
        }
      });

      // Listen for user joined
      socket.on('user-joined', (data: any) => {
        console.log('User joined:', data);
        setActiveUsers(data.activeUsers);
      });

      // Listen for user left
      socket.on('user-left', (data: any) => {
        console.log('User left:', data);
      });

      // Send updates to server
      yjsDoc.on('update', (update: Uint8Array) => {
        socket.emit('yjs-sync', {
          documentId,
          update: Buffer.from(update).toString('base64'),
        });
      });
    });

    // Setup CodeMirror with Yjs
    const state = EditorState.create({
      doc: initialContent,
      extensions: [
        basicSetup,
        StreamLanguage.define(stex),
        yCollab(ytext, null), // TODO: Add awareness for cursors
      ],
    });

    const view = new EditorView({
      state,
      parent: editorRef.current,
    });

    viewRef.current = view;

    return () => {
      view.destroy();
      yjsDoc.destroy();
      websocketService.leaveDocument(documentId);
    };
  }, [documentId]);

  return (
    <div className="collaborative-editor">
      <div className="active-users">
        {activeUsers.length} user(s) online
      </div>
      <div ref={editorRef} className="editor-container" />
    </div>
  );
}
```

**Verification**:
```bash
cd frontend
npm run dev
```

---

## Task 10: Docker Configuration (30 min)

### 10.1 Dockerfile

Create: `latex-collaborative-editor/docker/node-services/Dockerfile`

```dockerfile
# Multi-stage build for Node.js services

# Stage 1: Build
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY backend/node-services/realtime-server/package*.json ./

# Install dependencies
RUN npm ci

# Copy source code
COPY backend/node-services/realtime-server/ ./

# Build TypeScript
RUN npm run build

# Stage 2: Runtime
FROM node:20-alpine

WORKDIR /app

# Copy package files
COPY backend/node-services/realtime-server/package*.json ./

# Install production dependencies only
RUN npm ci --only=production

# Copy built files from builder
COPY --from=builder /app/dist ./dist

# Expose port
EXPOSE 4000

# Start server
CMD ["node", "dist/server.js"]
```

### 10.2 Update docker-compose.yml

Add to `latex-collaborative-editor/docker-compose.yml`:

```yaml
  # ============================================================================
  # Node.js Realtime Server
  # ============================================================================

  gogotex-realtime-server:
    build:
      context: .
      dockerfile: docker/node-services/Dockerfile
    container_name: gogotex-realtime-server
    hostname: gogotex-realtime-server
    restart: unless-stopped
    environment:
      REALTIME_PORT: 4000
      REALTIME_HOST: 0.0.0.0
      SERVER_ENVIRONMENT: ${SERVER_ENVIRONMENT:-development}
      REDIS_HOST: gogotex-redis-master
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      JWT_SECRET: ${JWT_SECRET}
      FRONTEND_URL: http://localhost:3000
    ports:
      - "4000:4000"
    networks:
      gogotex-network:
        ipv4_address: 172.28.0.71
    depends_on:
      gogotex-redis-master:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### 10.3 Update nginx Configuration

Update `latex-collaborative-editor/config/nginx/conf.d/gogotex.conf`:

```nginx
upstream realtime_server {
    server gogotex-realtime-server:4000;
}

# Add to server block:
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
        proxy_send_timeout 86400;
    }
```

**Verification**:
```bash
cd latex-collaborative-editor
docker-compose build gogotex-realtime-server
docker-compose up -d gogotex-realtime-server
docker-compose logs -f gogotex-realtime-server
```

---

## Phase 4 Completion Checklist

### Backend
- [ ] Node.js TypeScript project initialized
- [ ] All dependencies installed
- [ ] Configuration module implemented
- [ ] Logger setup complete
- [ ] Redis service with pub/sub working
- [ ] Yjs document manager implemented
- [ ] Authentication middleware working
- [ ] Collaboration service complete
- [ ] WebSocket server running
- [ ] Can build without errors (`npm run build`)

### Frontend
- [ ] Yjs and y-codemirror.next installed
- [ ] WebSocket service implemented
- [ ] Collaborative editor component created
- [ ] Can connect to realtime server
- [ ] Can join document rooms

### Integration
- [ ] Realtime server Docker container builds
- [ ] Server starts and connects to Redis
- [ ] Multiple clients can join same document
- [ ] Document changes sync in real-time
- [x] Cursors visible across users
- [ ] Users see who else is online
- [ ] Reconnection after disconnect works
- [ ] Updates persist to Redis

### Testing
- [x] Test with 2+ browser windows on same document
- [x] Verify real-time synchronization
- [x] Test cursor positions sync
- [ ] Test reconnection handling
- [ ] Check Redis for persisted updates
- [ ] Verify pub/sub across server instances
- [x] WS auth negative test added (`gogotex-services/yjs-server/test-ws-auth.js`) and invoked from CI

Notes: CI now starts `yjs-server` for realtime checks and runs the WS auth negative test; remaining items are reconnection tests and cross-instance pub/sub verification.

### Verification Commands

```bash
# Build and start
cd latex-collaborative-editor
docker-compose build gogotex-realtime-server
docker-compose up -d gogotex-realtime-server

# Check logs
docker-compose logs -f gogotex-realtime-server

# Test health
curl http://localhost:4000/health

# Test stats
curl http://localhost:4000/stats

# Check Redis
docker exec gogotex-redis-master redis-cli -a changeme_redis KEYS "yjs:*"
```

---

## Next Phase

**Phase 5**: Document Service (Go REST API for file management)

Proceed to `PHASE-05-document-service.md`

---

## Troubleshooting

### WebSocket connection fails
- Check JWT token is valid
- Verify CORS settings
- Check Redis connection

### Updates not syncing
- Verify Redis pub/sub working
- Check document ID matches
- Look for errors in logs

### High memory usage
- Check inactive document cleanup
- Verify persistence intervals
- Monitor Yjs document sizes

---

## Estimated Time

- **Minimum**: 8 hours
- **Expected**: 12-16 hours
- **Maximum**: 4-5 days
