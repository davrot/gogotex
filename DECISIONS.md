# GoGoLaTeX - Project Decisions Summary

## Quick Reference

### Core Decisions Made

| Decision Area | Choice | Rationale |
|--------------|--------|-----------|
| **Editor** | CodeMirror 6 | Mobile support, lightweight (200KB vs 2.5MB), touch-friendly |
| **Compilation** | WASM + Docker (user choice) | User selects engine, WASM for speed, Docker for reliability |
| **LaTeX Packages** | TeX Live Full | All packages pre-installed, no custom installation |
| **Container Naming** | `gogolatex-*` | Consistent branding (changed from `texlyre-*`) |
| **Network Name** | `gogolatex-network` | Matches project name |
| **Plugin Architecture** | Frontend + Backend hybrid | Plugins can have both components |
| **Mobile Support** | Yes - Full editing | Primary reason for CodeMirror 6 selection |
| **Offline Support** | No | Online-first, users can export for offline |
| **Billing/Quotas** | No | Simple deployment, optional future |
| **Templates** | Yes | Built-in gallery with common document types |
| **Reference Managers** | Yes (via plugins) | DOI, ORCID, Zotero, Mendeley |
| **Access Control** | 4-tier (Owner/Editor/Reviewer/Reader) | Granular permissions |

---

## Detailed Decisions

### 1. Editor: CodeMirror 6 ✅

**Why CodeMirror 6 over Monaco**:
- ✅ **Mobile support** - Touch-friendly, mobile-optimized
- ✅ **Lightweight** - 200KB vs Monaco's 2.5MB (10x smaller)
- ✅ **Performance** - Better on mobile devices
- ✅ **Yjs integration** - Excellent `y-codemirror.next` bindings
- ✅ **Customizable** - Can achieve VS Code-like aesthetic

**Trade-offs Accepted**:
- Need to build some features from scratch
- Custom LaTeX IntelliSense implementation required
- Diff editor requires custom implementation

---

### 2. Compilation: User Choice (WASM/Docker) ✅

**User Settings**:
```typescript
compilationSettings: {
  engine: "auto" | "wasm" | "docker",
  autoFallback: boolean,
  showEngineChoice: boolean
}
```

**Benefits**:
- ✅ Power users can force Docker for reliability
- ✅ Users on fast connections can choose WASM
- ✅ Mobile users default to Docker
- ✅ Testing: Compare WASM vs Docker results

**Engines**:
- **SwiftLaTeX WASM**: Client-side, instant, free
- **Docker (TeX Live Full)**: Server-side, all packages, reliable

---

### 3. LaTeX Packages: TeX Live Full ✅

**Decision**: No custom package installation

**Rationale**:
- ✅ All standard packages available
- ✅ No security risk from user-uploaded packages
- ✅ Faster compilation (pre-installed)
- ✅ Consistent environment

**If users need missing packages**:
- Users can request
- We add to base Docker image
- Everyone benefits

---

### 4. Naming Convention: gogolatex-* ✅

**Changed from**: `texlyre-*`  
**Changed to**: `gogolatex-*`

**Affected Components**:
- Container names: `gogolatex-mongodb`, `gogolatex-redis`, etc.
- Network name: `gogolatex-network`
- Database name: `gogolatex`
- Replica set: `gogolatex`
- Keycloak realm: `gogolatex`
- Service hostnames

---

### 5. Plugin Architecture: Frontend + Backend ✅

**Key Principle**: Plugins can have frontend and/or backend components

**Plugin Types**:
1. **Frontend only**: UI extensions, editor features
2. **Backend only**: Processing services, APIs
3. **Hybrid**: Both frontend and backend

**Plugin Manifest**:
```json
{
  "id": "plugin-id",
  "type": "hybrid",
  "frontend": { "main": "dist/frontend.js" },
  "backend": { 
    "type": "docker",
    "image": "gogolatex-plugins/plugin:1.0.0"
  }
}
```

---

### 6. Mobile Support: Yes ✅

**Implementation**:
- CodeMirror 6 (touch-friendly)
- Responsive design
- Mobile-optimized toolbar
- Bottom action bars (thumb-friendly)
- Virtual keyboard support
- Docker compilation (server-side)

**Mobile Features**:
- ✅ Full editing
- ✅ Real-time collaboration
- ✅ PDF preview
- ✅ Comments and chat
- ✅ Change tracking
- ⚠️ Simplified UI (essential features only)

---

### 7. Templates: Yes ✅

**Built-in Templates**:
- Academic paper (ACM, IEEE, Springer)
- Thesis/Dissertation
- Resume/CV
- Letter
- Presentation (Beamer)
- Book
- Article

**Storage**: MinIO (`templates/` directory)

---

### 8. Reference Managers: Yes (via plugins) ✅

**Priority Order**:

**Tier 1 (High Priority)**:
1. **DOI Fetcher** - CrossRef/DataCite API
2. **ORCID** - Author identification, publications
3. **Zotero** - Web API, collections, sync

**Tier 2 (Medium Priority)**:
4. **Mendeley** - API integration (maybe)

**Implementation**: Hybrid plugins (frontend + backend)

---

### 9. Access Control: 4-Tier System ✅

**Roles**:

1. **Owner**
   - Full control
   - Delete project
   - Manage collaborators
   - Transfer ownership

2. **Editor**
   - Edit all documents
   - Create/delete files
   - Compile
   - Accept/reject changes
   - Add comments

3. **Reviewer**
   - View documents
   - Add comments
   - Track changes (suggest edits)
   - Cannot: Direct edit, accept/reject

4. **Reader**
   - View documents
   - View PDF
   - Download
   - Cannot: Edit, comment, chat

**Additional Features**:
- Anonymous sharing links (read-only)
- Expiring access
- Activity log (audit trail)

---

### 10. No Offline Support ❌

**Rationale**:
- Complex sync logic
- Not priority for collaborative editor
- Online-first design simplifies architecture

**Alternative**:
- Export as ZIP
- Git sync (work locally)
- Re-import when online

---

### 11. No Billing/Quotas ❌

**Rationale**:
- Simple deployment
- No payment processing
- Suitable for institutional/self-hosted

**Optional Future**:
- Storage limits
- Rate limiting via Redis
- User quotas in MongoDB

---

## Architecture Summary

### Storage (2-Tier)
```
Yjs (in-memory) → Redis (hot) → MinIO (cold/source of truth)
                                    ↓
                                MongoDB (metadata only)
```

### Compilation (Hybrid)
```
User Choice:
  - Auto: Detect capability → WASM or Docker
  - WASM: SwiftLaTeX (client-side)
  - Docker: TeX Live Full (server-side)
```

### Services
```
- Go Services: Auth, Document, Compiler
- Node.js: Yjs real-time, Git operations
- Frontend: React + CodeMirror 6
- Infrastructure: MongoDB, Redis, MinIO, Keycloak
```

### Scaling
```
- Multiple Go instances (stateless)
- Multiple Node.js instances (Redis pub/sub)
- Redis cluster
- MongoDB replica set
- MinIO distributed
- LaTeX worker pool
```

---

## Next Steps

### Phase 1: Foundation
1. Docker Compose with `gogolatex-*` naming
2. Keycloak + Go auth service
3. CodeMirror 6 basic setup
4. Yjs collaboration
5. Redis pub/sub

### Phase 2: Core Features
6. WASM + Docker compilation (user choice)
7. 4-tier access control
8. Template gallery
9. Mobile UI optimization

### Phase 3: Extensions
10. Plugin system (frontend/backend)
11. DOI fetcher plugin
12. ORCID plugin
13. Zotero plugin
14. BibTeX editor

---

## Project Metadata

- **Project Name**: GoGoLaTeX
- **Container Prefix**: `gogolatex-`
- **Network**: `gogolatex-network`
- **Database**: `gogolatex`
- **Based On**: texlyre_docker architecture (davrot/texlyre_docker)
- **Target Users**: 1000+ concurrent users
- **Mobile**: Full support
- **Editor**: CodeMirror 6
- **Compilation**: WASM + Docker (TeX Live Full)
