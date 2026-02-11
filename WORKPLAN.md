# GoGoLaTeX - Implementation Workplan

## Overview

This workplan breaks down the GoGoLaTeX implementation into 8 phases, each with detailed tasks optimized for GitHub Copilot execution. Each phase builds upon the previous one, ensuring a stable, testable foundation.

## Project Structure

```
gogotex/
├── WORKPLAN.md                    # This file - Master workplan
├── plan.md                        # Technical architecture document
├── DECISIONS.md                   # Can be deleted (integrated into plan.md)
├── phases/
│   ├── PHASE-01-infrastructure.md      # Docker Compose, databases, Keycloak
│   ├── PHASE-02-go-auth-service.md     # Authentication service in Go
│   ├── PHASE-03-frontend-basics.md     # React + CodeMirror 6 setup
│   ├── PHASE-04-realtime-collab.md     # Node.js Yjs server + integration
│   ├── PHASE-05-document-service.md    # Go document CRUD + MinIO
│   ├── PHASE-06-compilation.md         # WASM + Docker LaTeX compilation
│   ├── PHASE-07-advanced-features.md   # Change tracking, comments, Git sync
│   └── PHASE-08-plugins-polish.md      # Plugin system, templates, deployment
└── latex-collaborative-editor/    # Main application code (created during phases)
```

## Phase Breakdown

### Phase 1: Infrastructure & Foundation (3-5 days)
**File**: `phases/PHASE-01-infrastructure.md`

- Docker Compose setup with all services
- MongoDB replica set configuration
- Redis cluster setup
- MinIO distributed storage
- Keycloak installation and realm configuration
- nginx reverse proxy
- Health checks and monitoring (Prometheus + Grafana)

**Deliverable**: Working infrastructure stack, all services healthy

---

### Phase 2: Go Authentication Service (2-3 days)
**File**: `phases/PHASE-02-go-auth-service.md`

- Go project structure
- OIDC integration with Keycloak
- JWT token generation and validation
- User registration and login endpoints
- MongoDB user model
- Rate limiting middleware
- OpenAPI/Swagger documentation
- Unit tests

**Deliverable**: Working auth API with JWT tokens

---

### Phase 3: Frontend Basics (3-4 days)
**File**: `phases/PHASE-03-frontend-basics.md`

- React + TypeScript + Vite setup
- CodeMirror 6 integration
- LaTeX syntax highlighting
- Basic UI layout (VS Code-inspired)
- Authentication flow (login/logout)
- Protected routes
- Mobile-responsive design foundation
- State management (Zustand)

**Deliverable**: Working frontend with editor and auth

---

### Phase 4: Real-time Collaboration (4-5 days)
**File**: `phases/PHASE-04-realtime-collab.md`

- Node.js WebSocket server (Socket.io)
- Yjs document synchronization
- Redis pub/sub for multi-server
- y-codemirror.next integration
- Live cursors and selections
- Presence awareness
- Connection management
- Conflict-free merging

**Deliverable**: Multi-user real-time editing

---

### Phase 5: Document Service (3-4 days)
**File**: `phases/PHASE-05-document-service.md`

- Go document REST API
- Project CRUD operations
- File management (create, read, update, delete)
- MinIO integration for .tex files
- MongoDB metadata storage
- 4-tier access control (Owner/Editor/Reviewer/Reader)
- Project sharing
- Version history tracking

**Deliverable**: Complete document management system

---

### Phase 6: LaTeX Compilation (4-5 days)
**File**: `phases/PHASE-06-compilation.md`

- SwiftLaTeX WASM integration (frontend)
- Docker compilation service (Go)
- TeX Live Full Docker image
- Compilation queue (Redis + Bull)
- Worker pool management
- PDF generation and storage
- Error handling and logs
- User-selectable engine (auto/wasm/docker)
- Compilation history

**Deliverable**: Working LaTeX compilation with both engines

---

### Phase 7: Advanced Features (5-7 days)
**File**: `phases/PHASE-07-advanced-features.md`

- Change tracking system (JSON files)
- Comments system
- Real-time chat
- Git sync service (Node.js)
- Email notifications (SMTP)
- Template gallery
- BibTeX editor
- Search functionality
- Activity logs

**Deliverable**: Full-featured collaborative editor

---

### Phase 8: Plugins & Production Polish (4-6 days)
**File**: `phases/PHASE-08-plugins-polish.md`

- Plugin system architecture
- Plugin loader (frontend + backend)
- DOI fetcher plugin
- ORCID integration plugin
- Zotero plugin (Tier 1)
- Mobile UI optimizations
- Performance optimization
- E2E tests (Playwright)
- Production deployment guide
- User documentation (MkDocs)

**Deliverable**: Production-ready application with plugins

---

## Total Timeline

**Estimated**: 28-43 days (4-6 weeks) for solo developer

**Fast Track** (minimal features): ~4 weeks  
**Complete** (all features): ~6 weeks  
**Polish + Plugins**: +1-2 weeks

---

## Copilot Optimization Strategy

Each phase file includes:

1. **Clear File Structure**: Exact paths and file names
2. **Code Templates**: Starter code with `// TODO:` comments for Copilot
3. **Function Signatures**: Complete type definitions for Copilot inference
4. **Test Cases**: Test stubs that Copilot can complete
5. **Comments**: Descriptive comments explaining what code should do
6. **Examples**: Working examples for similar patterns
7. **Checklists**: Task-by-task verification steps

---

## How to Use This Workplan

### For Each Phase:

1. **Read the phase file** (e.g., `phases/PHASE-01-infrastructure.md`)
2. **Follow tasks sequentially** - each builds on the previous
3. **Use Copilot** - The detailed comments and structure are optimized for Copilot suggestions
4. **Test as you go** - Each task has verification steps
5. **Mark complete** - Check off tasks in the phase file
6. **Move to next phase** - Only when current phase is 100% complete

### Copilot Tips:

- **Let Copilot write boilerplate**: It's trained on common patterns (Docker, Go, React)
- **Use descriptive comments**: `// Create JWT token with 15 min expiry and user claims`
- **Type hints help**: Complete function signatures help Copilot understand context
- **Accept and refine**: Take Copilot suggestions and modify as needed
- **Test-driven**: Write test cases first, let Copilot implement

---

## Prerequisites

Before starting Phase 1:

- [ ] Docker and Docker Compose installed
- [ ] Go 1.21+ installed
- [ ] Node.js 20+ and npm installed
- [ ] Git installed
- [ ] VS Code with GitHub Copilot enabled
- [ ] Basic understanding of Go, TypeScript, React
- [ ] Access to a domain (for SSL testing) or use localhost

---

## Success Criteria

### Phase 1-2: Infrastructure + Auth
- [ ] All Docker services running
- [ ] Keycloak accessible
- [ ] Users can register and login
- [ ] JWT tokens validated

### Phase 3-4: Frontend + Collaboration
- [ ] Users can see editor
- [ ] Multiple users can edit same document
- [ ] Changes sync in real-time
- [ ] Cursors visible across users

### Phase 5-6: Documents + Compilation
- [ ] Users can create/edit projects
- [ ] Files stored in MinIO
- [ ] LaTeX compiles to PDF
- [ ] Both WASM and Docker work

### Phase 7-8: Complete Application
- [ ] Change tracking works
- [ ] Comments functional
- [ ] Git sync operational
- [ ] Plugins load and work
- [ ] Mobile UI responsive
- [ ] E2E tests pass

---

## Next Steps

1. Review the complete architecture in `plan.md`
2. Start with **Phase 1**: `phases/PHASE-01-infrastructure.md`
3. Work through phases sequentially
4. Test thoroughly at each step
5. Deploy and iterate

---

## Emergency Decision Matrix

If you encounter issues during implementation:

| Issue | Decision Path |
|-------|--------------|
| **Keycloak too complex** | Simplify: Use local JWT auth, add OIDC later |
| **Yjs sync issues** | Fallback: Simple WebSocket with manual merge |
| **WASM compilation slow** | Prioritize Docker, make WASM optional |
| **MongoDB performance** | Add indexes, consider caching in Redis |
| **Redis cluster complex** | Start single-node, cluster when scaling |
| **MinIO setup hard** | Use local filesystem, migrate later |
| **Mobile UI poor** | Focus desktop first, optimize mobile in Phase 8 |
| **Plugin system delayed** | Build core features as built-ins first |

---

## Support Resources

- **plan.md**: Complete technical architecture
- **Phase files**: Detailed task breakdowns
- **GitHub Copilot**: Code completion and suggestions
- **Official docs**:
  - Go: https://go.dev/doc/
  - React: https://react.dev/
  - Yjs: https://docs.yjs.dev/
  - CodeMirror: https://codemirror.net/
  - Docker: https://docs.docker.com/

---

**Ready to start? Open `phases/PHASE-01-infrastructure.md`**
