# GogoLaTeX Implementation Guide for LLM

**Target Audience**: AI Assistant (GitHub Copilot, Claude, GPT-4, etc.) implementing this workplan  
**Project**: GogoLaTeX - Collaborative LaTeX Editor  
**Last Updated**: February 10, 2026

---

## 🎯 Mission Overview

You are tasked with implementing a **production-ready collaborative LaTeX editor** based on the detailed workplan in the `/phases` directory. This guide provides critical context, best practices, and strategies for successful implementation.

---

## 📋 Quick Start Checklist

Before starting implementation:

- [ ] Read this entire guide carefully
- [ ] Review all 8 phase files in `/phases` directory
- [ ] Understand the technology stack (see below)
- [ ] Set up your workspace following Phase 1
- [ ] Familiarize yourself with the project structure
- [ ] Note the verification steps in each task

---

## 🏗️ Architecture Overview

### System Design Philosophy

**GogoLaTeX follows a microservices architecture** with these principles:

1. **Service Independence**: Each service can be developed, deployed, and scaled independently
2. **Language Specialization**: Go for performance-critical services, Node.js for real-time features
3. **Data Isolation**: Each service manages its own data, communicates via APIs
4. **Event-Driven**: Real-time collaboration uses WebSocket + Redis pub/sub
5. **Stateless Services**: Services are stateless for horizontal scaling

### Technology Stack

#### Backend
- **Go 1.21+**: Auth, Document, Compilation services (performance, concurrency)
- **Node.js 20+**: Real-time server, Git service (WebSocket, JS ecosystem)
- **MongoDB 7**: Primary database (document storage, user data)
- **Redis 7**: Caching, pub/sub, session storage (auth service supports Redis-backed sessions), queue management
- **MinIO**: Object storage for large files (PDFs, images)
- **Keycloak**: Authentication and authorization (OIDC provider)

#### Frontend
- **React 18**: UI framework
- **TypeScript 5**: Type safety
- **Vite**: Build tool (fast HMR)
- **CodeMirror 6**: LaTeX editor
- **Yjs**: CRDT for conflict-free collaboration
- **Zustand**: State management (lighter than Redux)
- **Tailwind CSS**: Styling

#### Infrastructure
- **Docker**: Containerization
- **Docker Compose**: Local orchestration
- **Nginx**: Reverse proxy (production)

---

## 🚀 Implementation Strategy

### Phase Execution Order

**CRITICAL**: Implement phases **sequentially** (1 → 8). Each phase builds on previous phases.

| Phase | Duration | Critical Path? | Can Skip Temporarily? |
|-------|----------|----------------|----------------------|
| Phase 1: Infrastructure | 2-3 days | ✅ YES | ❌ NO - Foundation |
| Phase 2: Go Auth Service | 2-3 days | ✅ YES | ❌ NO - Required for all services |
| Phase 3: Frontend Basics | 3-4 days | ✅ YES | ❌ NO - User interface |
| Phase 4: Real-time Collab | 3-4 days | ✅ YES | ⚠️ Can defer, but core feature |
| Phase 5: Document Service | 3-4 days | ✅ YES | ❌ NO - CRUD operations |
| Phase 6: Compilation Service | 3-4 days | ✅ YES | ⚠️ Can defer for MVP |
| Phase 7: Advanced Features | 5-6 days | ⚠️ NO | ✅ YES - Post-MVP |
| Phase 8: Plugins & Polish | 4-5 days | ⚠️ NO | ✅ YES - Nice to have |

### Minimum Viable Product (MVP)

If time is constrained, focus on **Phases 1-5** first:
- Infrastructure setup
- Authentication working
- Basic frontend with editor
- Real-time collaboration
- Document CRUD operations

**Defer to Phase 2**:
- Phase 6: Compilation (can use external LaTeX service temporarily)
- Phase 7: Git, change tracking, comments (advanced features)
- Phase 8: Plugin system, templates, optimizations

---

## 💡 Implementation Tips

### 1. File Creation Order

For each phase task, create files in this order:

1. **Models/Types** first (data structures)
2. **Repository layer** (database access)
3. **Service layer** (business logic)
4. **Handlers/Controllers** (HTTP/API layer)
5. **Main server** (wiring everything together)
6. **Tests** (verification)

### 2. Incremental Verification

**DO NOT** write all code at once. After each task:

```bash
# Backend (Go)
go build ./...           # Ensure it compiles
go test ./...            # Run tests
go run cmd/service/main.go  # Test manually

# Backend (Node.js)
npm run build            # TypeScript compilation
npm test                 # Run tests
npm run dev              # Test manually

# Frontend
npm run build            # Production build
npm run dev              # Development server
```

### 3. Error Handling Pattern

Every function should handle errors properly:

**Go Pattern**:
```go
func DoSomething(ctx context.Context, id string) (*Result, error) {
    if id == "" {
        return nil, fmt.Errorf("id is required")
    }
    
    result, err := repository.Find(ctx, id)
    if err != nil {
        return nil, fmt.Errorf("failed to find: %w", err)
    }
    
    return result, nil
}
```

**TypeScript Pattern**:
```typescript
async function doSomething(id: string): Promise<Result> {
    if (!id) {
        throw new Error('id is required')
    }
    
    try {
        const result = await repository.find(id)
        return result
    } catch (error) {
        console.error('Failed to find:', error)
        throw new Error(`Failed to find: ${error.message}`)
    }
}
```

### 4. Context Propagation

Always pass `context.Context` in Go for cancellation and timeout:

```go
// Good
func (s *Service) GetDocument(ctx context.Context, id string) (*Document, error) {
    return s.repo.FindByID(ctx, id)
}

// Bad - no context
func (s *Service) GetDocument(id string) (*Document, error) {
    return s.repo.FindByID(id)
}
```

### 5. Database Indexes

**ALWAYS** create indexes after defining models:

```go
// In repository constructor
func NewDocumentRepository(db *mongo.Database) *DocumentRepository {
    collection := db.Collection("documents")
    
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    
    // Create indexes
    collection.Indexes().CreateOne(ctx, mongo.IndexModel{
        Keys: bson.D{{Key: "projectId", Value: 1}, {Key: "path", Value: 1}},
        Options: options.Index().SetUnique(true),
    })
    
    return &DocumentRepository{collection: collection}
}
```

### 6. Environment Variables

Use `.env` files but **NEVER** commit secrets:

```bash
# .env (local development)
MONGODB_URI=mongodb://localhost:27017/gogolatex
JWT_SECRET=dev-secret-change-in-production

# .env.prod (production - keep secure)
MONGODB_URI=mongodb://mongo1:27017,mongo2:27017,mongo3:27017/gogolatex?replicaSet=rs0
JWT_SECRET=<use strong random secret>
```

### 7. API Response Format

Consistent JSON responses:

```typescript
// Success
{
    "data": { /* response data */ },
    "message": "Success"
}

// Error
{
    "error": "Error message",
    "code": "ERROR_CODE"
}

// List with pagination
{
    "data": [ /* items */ ],
    "pagination": {
        "page": 1,
        "pageSize": 20,
        "total": 100
    }
}
```

### 8. WebSocket Message Format

Consistent WebSocket messages:

```typescript
// Client to Server
{
    "type": "document.update",
    "documentId": "...",
    "update": { /* Yjs update */ }
}

// Server to Client
{
    "type": "document.updated",
    "documentId": "...",
    "userId": "...",
    "update": { /* Yjs update */ }
}
```

---

## ⚠️ Common Pitfalls to Avoid

### 1. MongoDB Connection Issues

**Problem**: Services fail with "connection refused"  
**Solution**: Ensure MongoDB is ready before starting services

```bash
# Wait for MongoDB to be ready
until docker exec mongo1 mongosh --eval "db.adminCommand('ping')"; do
    echo "Waiting for MongoDB..."
    sleep 2
done
```

### 2. MongoDB Replica Set Not Initialized

**Problem**: Services can't connect to replica set  
**Solution**: Initialize replica set after starting containers

```bash
docker exec -it mongo1 mongosh --eval "rs.initiate({
    _id: 'rs0',
    members: [
        {_id: 0, host: 'mongo1:27017'},
        {_id: 1, host: 'mongo2:27017'},
        {_id: 2, host: 'mongo3:27017'}
    ]
})"
```

### 3. CORS Issues

**Problem**: Frontend can't call backend APIs  
**Solution**: Configure CORS properly

```go
// Go service
import "github.com/rs/cors"

corsHandler := cors.New(cors.Options{
    AllowedOrigins:   []string{"http://localhost:5173", "http://localhost:3000"},
    AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
    AllowedHeaders:   []string{"Authorization", "Content-Type"},
    AllowCredentials: true,
})

handler := corsHandler.Handler(router)
```

### 4. JWT Token Expiration

**Problem**: Users get logged out unexpectedly  
**Solution**: Implement refresh token mechanism (Phase 2)

### 5. Real-time Sync Conflicts

**Problem**: Multiple users editing causes data corruption  
**Solution**: Use Yjs CRDT properly (Phase 4)

```typescript
// ALWAYS use Yjs transactions
doc.transact(() => {
    ytext.insert(0, 'Hello')
    ytext.delete(5, 3)
})
```

### 6. Memory Leaks in WebSocket

**Problem**: Server memory grows continuously  
**Solution**: Clean up connections properly

```typescript
socket.on('disconnect', () => {
    // Remove from tracking
    connections.delete(socket.id)
    
    // Clean up Yjs documents
    if (ydoc) {
        ydoc.destroy()
    }
})
```

### 7. Large File Uploads

**Problem**: MongoDB document size limit (16MB)  
**Solution**: Use MinIO for files > 100KB (Phase 5)

```go
const ContentStorageThreshold = 100 * 1024 // 100KB

if len(content) > ContentStorageThreshold {
    // Store in MinIO
    url, err := minioService.Upload(content)
} else {
    // Store in MongoDB
    doc.Content = content
}
```

### 8. Docker Build Cache Issues

**Problem**: Changes not reflected in containers  
**Solution**: Force rebuild

```bash
docker-compose build --no-cache service-name
docker-compose up -d --force-recreate service-name
```

---

## 🔍 Debugging Strategies

### 1. Check Service Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f document-service

# Last 50 lines
docker-compose logs --tail=50 document-service
```

### 2. Check Service Health

```bash
# Health endpoint
curl http://localhost:8080/health

# MongoDB
docker exec mongo1 mongosh --eval "rs.status()"

# Redis
docker exec redis-master redis-cli PING
docker exec redis-master redis-cli INFO

# MinIO
curl http://localhost:9000/minio/health/live
```

### 3. Network Issues

```bash
# Check if services can communicate
docker exec auth-service ping -c 3 mongo1
docker exec auth-service ping -c 3 redis-master

# Check Docker network
docker network inspect gogolatex-network
```

### 4. Database Issues

```bash
# Check MongoDB collections
docker exec mongo1 mongosh gogolatex --eval "show collections"
docker exec mongo1 mongosh gogolatex --eval "db.documents.countDocuments()"

# Check indexes
docker exec mongo1 mongosh gogolatex --eval "db.documents.getIndexes()"

# Check Redis keys
docker exec redis-master redis-cli KEYS "*"
docker exec redis-master redis-cli GET "key-name"
```

### 5. Frontend Debugging

```javascript
// Enable debug mode in browser console
localStorage.setItem('debug', '*')

// Check WebSocket connection
const ws = new WebSocket('ws://localhost:3003')
ws.onopen = () => console.log('Connected')
ws.onerror = (err) => console.error('WS Error:', err)
ws.onmessage = (msg) => console.log('WS Message:', msg)
```

---

## 📦 Code Organization

### Go Project Structure

```
backend/go-services/
├── cmd/                    # Entry points
│   ├── auth/
│   │   └── main.go
│   ├── document/
│   │   └── main.go
│   └── compiler/
│       └── main.go
├── internal/               # Private packages
│   ├── auth/
│   │   ├── handler/       # HTTP handlers
│   │   ├── service/       # Business logic
│   │   └── repository/    # Database access
│   ├── models/            # Shared models
│   ├── database/          # Database connections
│   └── middleware/        # HTTP middleware
├── pkg/                   # Public packages
│   ├── logger/
│   └── validator/
├── go.mod
└── go.sum
```

### Node.js Project Structure

```
backend/node-services/
├── realtime-server/
│   ├── src/
│   │   ├── server.ts      # Main entry point
│   │   ├── websocket.ts   # WebSocket handler
│   │   ├── collaboration.ts # Yjs logic
│   │   └── types/         # TypeScript types
│   ├── package.json
│   └── tsconfig.json
└── git-service/
    ├── src/
    │   ├── server.ts
    │   ├── git-operations.ts
    │   └── controllers/
    ├── package.json
    └── tsconfig.json
```

### Frontend Structure

```
frontend/
├── src/
│   ├── App.tsx            # Root component
│   ├── main.tsx           # Entry point
│   ├── components/        # React components
│   │   ├── Editor.tsx
│   │   ├── Sidebar.tsx
│   │   └── Comments.tsx
│   ├── services/          # API services
│   │   ├── api.ts
│   │   └── websocket.ts
│   ├── stores/            # Zustand stores
│   │   └── authStore.ts
│   ├── types/             # TypeScript types
│   │   └── index.ts
│   └── utils/             # Utilities
├── package.json
├── tsconfig.json
├── vite.config.ts
└── tailwind.config.js
```

---

## 🧪 Testing Strategy

### Unit Tests

**Go**:
```go
func TestDocumentService_CreateDocument(t *testing.T) {
    // Setup
    service := NewDocumentService(mockRepo)
    
    // Execute
    doc, err := service.CreateDocument(context.Background(), req, user)
    
    // Assert
    assert.NoError(t, err)
    assert.NotNil(t, doc)
    assert.Equal(t, "test.tex", doc.Name)
}
```

**TypeScript**:
```typescript
describe('DocumentService', () => {
    it('should create document', async () => {
        const doc = await documentService.createDocument({
            name: 'test.tex',
            content: '\\documentclass{article}'
        })
        
        expect(doc).toBeDefined()
        expect(doc.name).toBe('test.tex')
    })
})
```

### Integration Tests

Test full API flows:

```bash
# Create project
PROJECT_ID=$(curl -X POST http://localhost:8080/api/projects \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name":"Test"}' | jq -r '.id')

# Create document
DOC_ID=$(curl -X POST http://localhost:8080/api/documents \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"projectId\":\"$PROJECT_ID\",\"name\":\"main.tex\"}" | jq -r '.id')

# Verify document exists
curl http://localhost:8080/api/documents/$DOC_ID \
    -H "Authorization: Bearer $TOKEN"
```

### Load Tests

Use tools like Apache Bench or k6:

```bash
# Install k6
brew install k6  # macOS
# or
apt-get install k6  # Linux

# Run load test
k6 run scripts/load-test.js
```

---

## 🔐 Security Checklist

- [ ] **Authentication**: JWT tokens with expiration
- [ ] **Authorization**: Role-based access control (RBAC)
- [ ] **Input Validation**: Sanitize all user inputs
- [x] **Rate Limiting**: Prevent API abuse (in-memory token-bucket; per-user when authenticated) — optional Redis-backed distributed limiter available via `RATE_LIMIT_USE_REDIS`
- [ ] **CORS**: Configure allowed origins
- [ ] **HTTPS**: Use SSL/TLS in production
- [ ] **Secrets**: Never commit secrets to Git
- [ ] **SQL Injection**: Use parameterized queries (N/A for MongoDB, but still validate)
- [ ] **XSS**: Escape HTML output
- [ ] **CSRF**: Use CSRF tokens for state-changing operations
- [ ] **Dependencies**: Regular security updates
- [ ] **Logging**: Don't log sensitive data

---

## 📊 Performance Targets

| Metric | Target | Critical? |
|--------|--------|-----------|
| API Response Time (p95) | < 100ms | ✅ |
| Document Load Time | < 500ms | ✅ |
| Real-time Sync Latency | < 50ms | ✅ |
| LaTeX Compilation Time | < 30s | ⚠️ |
| Frontend Bundle Size | < 1MB gzipped | ⚠️ |
| Concurrent Users | 1000+ per instance | ⚠️ |
| Database Query Time | < 50ms | ✅ |
| Memory Usage | < 512MB per service | ⚠️ |

---

## 🎓 Learning Resources

### Go
- [Effective Go](https://go.dev/doc/effective_go)
- [Go by Example](https://gobyexample.com/)
- [MongoDB Go Driver](https://pkg.go.dev/go.mongodb.org/mongo-driver/mongo)

### Node.js
- [Node.js Best Practices](https://github.com/goldbergyoni/nodebestpractices)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/handbook/intro.html)
- [Socket.io Documentation](https://socket.io/docs/)

### React
- [React Documentation](https://react.dev/)
- [CodeMirror 6 Guide](https://codemirror.net/docs/)
- [Yjs Documentation](https://docs.yjs.dev/)

### LaTeX
- [LaTeX Wikibook](https://en.wikibooks.org/wiki/LaTeX)
- [Overleaf Documentation](https://www.overleaf.com/learn)

---

## 🆘 When You're Stuck

### 1. Check the Phase Files
Each task has:
- Detailed implementation steps
- Complete code templates
- Verification commands
- Troubleshooting sections

### 2. Review Working Examples
Look at similar implementations in other tasks:
- Task 3 in Phase 5 shows repository pattern
- Task 4 in Phase 4 shows WebSocket handling
- Task 2 in Phase 3 shows React components

### 3. Verify Prerequisites
Is the previous phase working?
- Can services connect to databases?
- Are Docker containers running?
- Are environment variables set?

### 4. Check Common Issues
See **"Common Pitfalls to Avoid"** section above

### 5. Simplify and Test
- Comment out complex logic
- Test with minimal example
- Add debug logging
- Use curl to test APIs directly

---

## ✅ Implementation Checklist

Use this to track progress:

### Phase 1: Infrastructure ⬜
- [ ] Docker Compose configured
- [ ] MongoDB replica set working
- [ ] Redis cluster working
- [ ] MinIO accessible
- [ ] Keycloak configured

### Phase 2: Go Auth Service ⬜
- [ ] OIDC integration working
- [ ] JWT middleware functional
- [ ] User model created
- [ ] Auth endpoints responding

### Phase 3: Frontend Basics ⬜
- [ ] Vite project setup
- [ ] CodeMirror editor working
- [ ] Authentication flow complete
- [ ] API service configured

### Phase 4: Real-time Collaboration ⬜
- [ ] WebSocket connection stable
- [ ] Yjs CRDT working
- [ ] Multi-user editing functional
- [ ] Presence awareness showing

### Phase 5: Document Service ⬜
- [ ] Project CRUD working
- [ ] Document CRUD working
- [ ] MinIO integration complete
- [ ] File tree rendering

### Phase 6: Compilation Service ⬜
- [ ] WASM compiler working
- [ ] Docker compiler working
- [ ] Queue system functional
- [ ] PDF generation successful

### Phase 7: Advanced Features ⬜
- [ ] Git service operational
- [ ] Change tracking working
- [ ] Comments system functional
- [ ] Mobile UI responsive

### Phase 8: Plugins & Polish ⬜
- [ ] Plugin system working
- [ ] Templates available
- [ ] DOI/ORCID lookup working
- [ ] Performance optimized
- [ ] Security hardened
- [ ] Monitoring configured

---

## 🚢 Deployment

See `DEPLOYMENT.md` (created in Phase 8, Task 10) for complete deployment checklist.

**Quick Deploy**:
```bash
# Build all
docker-compose -f docker-compose.prod.yml build

# Start infrastructure
docker-compose -f docker-compose.prod.yml up -d mongo1 mongo2 mongo3 redis-master minio

# Initialize MongoDB
docker exec mongo1 mongosh --eval "rs.initiate()"

# Start services
docker-compose -f docker-compose.prod.yml up -d

# Verify
curl http://localhost/health
```

---

## 💬 Final Words

### Success Factors

1. **Follow the Plan**: Don't skip steps or jump ahead
2. **Test Incrementally**: Verify each task before moving on
3. **Read Error Messages**: They usually tell you exactly what's wrong
4. **Use Verification Steps**: Every task has them for a reason
5. **Keep It Simple**: Start with basic implementation, optimize later
6. **Document as You Go**: Add comments explaining complex logic
7. **Ask for Help**: Reference this guide and phase files

### Code Quality Principles

- **Readability > Cleverness**: Write code others can understand
- **Error Handling**: Always handle errors, never ignore them
- **Testing**: Write tests for critical paths
- **Performance**: Optimize after it works, not before
- **Security**: Never trust user input

### You've Got This! 🎉

This workplan provides **everything you need**:
- ✅ Complete architecture
- ✅ Detailed implementations
- ✅ Code templates
- ✅ Verification steps
- ✅ Troubleshooting guides
- ✅ Best practices

**Follow the phases, test incrementally, and you'll build an amazing collaborative LaTeX editor!**

---

## 📞 Quick Reference

| Need | Check |
|------|-------|
| MongoDB issues | Phase 1, Task 2-4 |
| Authentication | Phase 2, all tasks |
| Frontend setup | Phase 3, Task 1 |
| Editor integration | Phase 3, Task 4 |
| WebSocket setup | Phase 4, Task 1-2 |
| CRUD operations | Phase 5, Task 3-6 |
| Compilation | Phase 6, Task 5-7 |
| Git operations | Phase 7, Task 1-2 |
| Performance | Phase 8, Task 7 |
| Security | Phase 8, Task 8 |
| Deployment | Phase 8, Task 10 + DEPLOYMENT.md |

---

**Good luck with the implementation! 🚀**

**Remember**: This is a production-quality system. Take your time, test thoroughly, and build something amazing!
