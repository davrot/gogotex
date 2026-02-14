require('dotenv').config();
const jwt = require('jsonwebtoken');
const Y = require('yjs');
const { MongodbPersistence } = require('y-mongodb-provider');
const { createClient } = require('redis');
const http = require('http');
const WebSocket = require('ws');
const { setupWSConnection } = require('./yjs-server');

const PORT = process.env.WS_PORT || 1234;
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/texlyre';
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';
const REDIS_CACHE_TTL = parseInt(process.env.REDIS_CACHE_TTL) || 3600; // max seconds to cache compile metadata in Redis

const JWT_SECRET = process.env.JWT_SECRET || '';
const AUTH_REQUIRED = JWT_SECRET.length > 0;

console.log('Starting TeXlyre Yjs Server...');
console.log('MongoDB URI:', MONGODB_URI.replace(/\/\/.*:.*@/, '//***:***@'));
console.log('Redis URL:', REDIS_URL.replace(/\/\/.*:.*@/, '//***:***@'));
if (AUTH_REQUIRED) console.log('WebSocket authentication: ENABLED');
else console.log('WebSocket authentication: disabled (no JWT_SECRET)');

// Initialize MongoDB persistence
const mdb = new MongodbPersistence(MONGODB_URI, {
  flushSize: parseInt(process.env.MONGODB_FLUSH_SIZE) || 100,
  multipleCollections: process.env.MONGODB_MULTIPLE_COLLECTIONS === 'true',
});

console.log('✓ MongoDB persistence initialized');

// Initialize Redis cache
let redisClient = null;
if (process.env.REDIS_CACHE_ENABLED === 'true') {
  redisClient = createClient({ 
    url: REDIS_URL,
    socket: {
      reconnectStrategy: (retries) => {
        if (retries > 10) {
          console.error('Redis: Too many reconnection attempts');
          return new Error('Too many retries');
        }
        return Math.min(retries * 500, 3000);
      }
    }
  });
  
  redisClient.on('error', (err) => console.error('Redis Client Error:', err));
  redisClient.on('connect', () => console.log('✓ Redis cache connecting...'));
  redisClient.on('ready', () => console.log('✓ Redis cache ready'));
  redisClient.on('reconnecting', () => console.log('⚠ Redis cache reconnecting...'));
  
  redisClient.connect().catch((err) => {
    console.error('Failed to connect to Redis:', err);
    console.log('⚠ Continuing without Redis cache');
    redisClient = null;
  });

  // Subscribe to compile metadata updates published by backend services
  (async () => {
    if (!redisClient) return;
    try {
      await redisClient.subscribe('compile:updates', async (message) => {
        try {
          const payload = JSON.parse(message);
          const docId = payload.docId || payload.docID || payload.documentId;
          if (!docId) return;

          // cache compile metadata for quick retrieval via HTTP
          try {
            await redisClient.setEx(`compile:doc:${docId}`, REDIS_CACHE_TTL, JSON.stringify(payload));
          } catch (e) {
            console.error('[Redis] failed to cache compile metadata:', e.message);
          }

          // broadcast to any WebSocket clients currently connected to the document
          wss.clients.forEach((client) => {
            try {
              if (client.readyState === WebSocket.OPEN && client.docName === docId) {
                client.send(JSON.stringify({ type: 'compile-update', payload }));
              }
            } catch (e) { /* ignore per-client failures */ }
          });

          console.log(`[compile] broadcasted update for doc=${docId}`);
        } catch (err) {
          console.error('Error handling compile:updates message:', err);
        }
      });
      console.log('Subscribed to compile:updates channel');
    } catch (err) {
      console.error('Failed to subscribe to compile:updates:', err);
    }
  })();
}

// Create HTTP server
const server = http.createServer(async (request, response) => {
  try {
    const base = `http://${request.headers.host || 'localhost'}`;
    const url = new URL(request.url, base);

    // Health endpoint
    if (request.method === 'GET' && url.pathname === '/health') {
      const health = {
        status: 'healthy',
        redis: redisClient && redisClient.isOpen ? 'ready' : 'disabled',
        mongodb: mdb ? 'initialized' : 'disabled',
        uptime: process.uptime(),
      };
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify(health));
      return;
    }

    // Simple API: return latest compile metadata cached for a document
    // GET /api/compile/:docId/latest
    const compileMatch = url.pathname.match(/^\/api\/compile\/([^\/]+)\/latest$/);
    if (request.method === 'GET' && compileMatch) {
      const docId = compileMatch[1];
      if (redisClient && redisClient.isOpen) {
        const cached = await redisClient.get(`compile:doc:${docId}`);
        if (cached) {
          response.writeHead(200, { 'Content-Type': 'application/json' });
          response.end(cached);
          return;
        }
      }
      response.writeHead(404, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ error: 'not_found' }));
      return;
    }

    // default info endpoint
    response.writeHead(200, { 'Content-Type': 'text/plain' });
    response.end('TeXlyre Yjs WebSocket Server\n');
  } catch (err) {
    console.error('HTTP handler error:', err);
    response.writeHead(500, { 'Content-Type': 'text/plain' });
    response.end('internal error');
  }
});

// Create WebSocket server
const wss = new WebSocket.Server({ 
  server,
  perMessageDeflate: {
    zlibDeflateOptions: {
      chunkSize: 1024,
      memLevel: 7,
      level: 3
    },
    zlibInflateOptions: {
      chunkSize: 10 * 1024
    },
    clientNoContextTakeover: true,
    serverNoContextTakeover: true,
    serverMaxWindowBits: 10,
    concurrencyLimit: 10,
    threshold: 1024
  }
});

wss.on('connection', (ws, req) => {
  const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress;
  console.log(`New connection from ${ip}`);

  // Optional JWT auth: accept token in query (?token=...) or in 'sec-websocket-protocol' header
  if (AUTH_REQUIRED) {
    const extractTokenFromReq = (r) => {
      try {
        const base = `http://${r.headers.host || 'localhost'}`;
        const u = new URL(r.url, base);
        const q = u.searchParams.get('token');
        if (q) return q;
      } catch (e) { /* ignore */ }
      const proto = r.headers['sec-websocket-protocol'] || r.headers['authorization'];
      if (!proto) return null;
      const token = String(proto).split(',')[0].trim();
      if (token.startsWith('Bearer ')) return token.slice(7);
      return token;
    };

    const token = extractTokenFromReq(req);
    if (!token) {
      console.warn('WebSocket connection rejected: missing token');
      ws.close(1008, 'Authentication required');
      return;
    }

    try {
      const payload = jwt.verify(token, JWT_SECRET);
      ws.user = payload;
      console.log('WebSocket authenticated ->', payload.sub || payload.email || '<user>');
    } catch (err) {
      console.warn('WebSocket authentication failed:', err.message);
      ws.close(1008, 'Unauthorized');
      return;
    }
  }
  
  setupWSConnection(ws, req, { 
    persistence: mdb,
    redis: redisClient,
  });
});

// Graceful shutdown
const shutdown = async (signal) => {
  console.log(`${signal} received, closing server...`);
  
  wss.clients.forEach((client) => {
    client.close();
  });
  
  wss.close();
  
  if (redisClient && redisClient.isOpen) {
    await redisClient.quit();
  }
  
  process.exit(0);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

server.listen(PORT, () => {
  console.log(`
╔════════════════════════════════════════╗
║   TeXlyre Yjs Server Running           ║
╠════════════════════════════════════════╣
║   Port: ${PORT.toString().padEnd(30)}║
║   MongoDB: ${mdb ? 'Connected'.padEnd(27) : 'Disabled'.padEnd(27)}║
║   Redis: ${redisClient ? 'Connected'.padEnd(29) : 'Disabled'.padEnd(29)}║
╚════════════════════════════════════════╝
  `);
});
