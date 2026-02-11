# Collaborative LaTeX Online Editor - Technical Plan

## Project Overview
A multi-user collaborative LaTeX editor with real-time editing, commenting, change tracking, and Git integration. The application will support multiple simultaneous users working on the same document with live cursor positions and changes visible to all participants.

## Core Requirements
1. **Multi-user real-time collaboration** - Multiple users editing simultaneously
2. **Change tracking** - Accept/reject changes (like Word's track changes)
3. **Comments system** - Users can leave comments on specific parts of the document
4. **Git integration** - Users can interact with LaTeX projects via Git
5. **Real-time chat** - Users can communicate while working
6. **User authentication** - OpenID Connect (Keycloak)
7. **LaTeX compilation** - Sandboxed Docker compilation
8. **VS Code-like UI** - Modern, familiar interface

---

## Tech Stack Analysis

### Backend Services

#### Go Services (REST APIs)
**Rationale**: Go is excellent for high-performance, concurrent services with low memory footprint.

1. **Auth Service** (Go)
   - OpenID Connect integration with Keycloak
   - JWT token validation and refresh
   - User session management
   - **Why Go**: Fast, secure, excellent crypto libraries

2. **Document Service** (Go)
   - Document CRUD operations
   - Project management
   - Version history
   - **Why Go**: Efficient for database operations and API endpoints

3. **Compiler Service** (Go)
   - Manages LaTeX compilation in Docker containers
   - Handles compilation queue
   - PDF generation and artifact management
   - **Why Go**: Great for orchestrating Docker containers, excellent concurrency

**Go Libraries**:
- `gin-gonic/gin` - Fast HTTP web framework
- `coreos/go-oidc` - OpenID Connect client
- `golang-jwt/jwt` - JWT handling
- `mongodb/mongo-go-driver` - MongoDB driver
- `go-redis/redis` - Redis client
- `minio/minio-go` - MinIO SDK

#### Node.js Services (WebSocket & Real-time)
**Rationale**: Node.js excels at WebSocket connections and real-time features with its event-driven architecture.

1. **Real-time Collaboration Server** (Node.js/TypeScript)
   - WebSocket server for real-time editing
   - Operational Transform (OT) or CRDT for conflict resolution
   - Live cursor positions and selections
   - Real-time chat
   - **Why Node.js**: Best-in-class WebSocket support, large ecosystem for real-time collaboration

2. **Git Service** (Node.js/TypeScript)
   - Git operations (clone, commit, push, pull, merge)
   - Branch management
   - Conflict resolution helpers
   - **Why Node.js**: Excellent Git libraries (nodegit/isomorphic-git), async I/O perfect for Git operations

**Node.js Libraries**:
- `ws` or `socket.io` - WebSocket implementation
- `yjs` or `sharedb` - CRDT/OT framework for collaborative editing
- `nodegit` or `isomorphic-git` - Git operations
- `express` - REST API framework
- `ioredis` - Redis client for pub/sub
- `mongodb` - MongoDB driver

### Frontend

#### React + TypeScript
**Rationale**: React with TypeScript provides type safety and a component-based architecture perfect for complex UIs.

**Key Libraries**:
- `@monaco-editor/react` - VS Code's editor (Monaco) for LaTeX editing
- `react-pdf` or `pdfjs-dist` - PDF preview
- `y-monaco` or `sharedb-monaco` - Monaco bindings for collaborative editing
- `@tanstack/react-query` - Server state management
- `zustand` or `redux-toolkit` - Client state management
- `tailwindcss` - VS Code-like styling made easy
- `websocket` or `socket.io-client` - Real-time connection

**UI Components**:
- Custom VS Code-inspired theme
- Split pane editor (LaTeX source + PDF preview)
- Comments sidebar
- Change tracking panel
- Chat panel
- Git integration panel

### Data Storage

#### MongoDB
**Use Cases**:
- User profiles and permissions
- Document metadata
- Project structures
- Comments and annotations
- Change history
- Chat messages

**Collections**:
```
users: { id, email, name, preferences, projects[] }
projects: { id, name, owner, collaborators[], settings }
documents: { id, projectId, path, metadata, permissions }
comments: { id, documentId, userId, position, content, thread[] }
changes: { id, documentId, userId, timestamp, diff, status }
chat_messages: { id, projectId, userId, timestamp, content }
```

**Why MongoDB**: 
- Flexible schema for document structures
- Good performance for read-heavy operations
- Native JSON support
- Horizontal scaling capabilities

#### Redis
**Use Cases**:
- Session storage (JWT tokens, user sessions)
- Real-time presence (who's online, cursor positions)
- Pub/Sub for real-time events across servers
- Compilation job queue
- Rate limiting
- Caching (compiled PDFs, document snapshots)

**Why Redis**:
- Extremely fast in-memory operations
- Built-in pub/sub for real-time features
- Perfect for session management
- Excellent for queuing compilation jobs

#### MinIO
**Use Cases**:
- LaTeX source files
- Compiled PDFs
- Project assets (images, bibliography files)
- Document versions/snapshots
- Git repository storage

**Bucket Structure**:
```
projects/{projectId}/sources/
projects/{projectId}/outputs/
projects/{projectId}/assets/
projects/{projectId}/git/
```

**Why MinIO**:
- S3-compatible object storage
- Self-hosted solution
- Versioning support
- Good for large files
- Efficient for binary assets

### LaTeX Compilation

#### Hybrid Compilation Strategy ✅

**Two-tier compilation approach** for optimal user experience:

**1. Client-Side WASM Compilation (SwiftLaTeX)**
- **Target users**: Desktop users with decent hardware (>4GB RAM)
- **Engine**: SwiftLaTeX WebAssembly engine
- **Benefits**:
  - ✅ **Instant compilation** (runs in browser)
  - ✅ **No server load** (scales infinitely)
  - ✅ **Offline capable** (works without connection)
  - ✅ **No queue** (immediate feedback)
  - ✅ **No cost** (client resources)

**2. Server-Side Docker Compilation (TeXLive)**
- **Target users**: Mobile, low-end devices, or WASM failures
- **Engine**: Full TeXLive in Docker sandbox
- **Benefits**:
  - ✅ **Complete package support** (all LaTeX packages)
  - ✅ **Reliable** (fallback for WASM failures)
  - ✅ **Complex documents** (large projects with many dependencies)

---

#### **Compilation Decision Flow**

**DECISION: User Choice** ✅

Users can select their preferred compilation method in settings or per-compilation:

```
User clicks "Compile"
         ↓
    Check user preference
         ↓
    ┌─────────────────────────────┐
    │  User Setting:              │
    │  [ Auto / WASM / Docker ]   │
    └──────────────┬──────────────┘
                   │
       ┌───────────┼───────────┐
       │           │           │
     AUTO        WASM       DOCKER
       │           │           │
       ↓           ↓           ↓
  Auto-detect  SwiftLaTeX   Docker
  (see below)    (WASM)    (Server)
       │           │           │
       └───────────┴───────────┘
                   ↓
              PDF Ready

Auto-detect logic:
1. Check device capability (Desktop + >4GB + WASM support)
2. If capable → Try WASM
3. If WASM fails → Fallback to Docker
4. If not capable → Docker directly
```

**User Settings**:
```typescript
compilationSettings: {
  engine: "auto" | "wasm" | "docker",
  autoFallback: boolean,  // Allow fallback if WASM fails
  showEngineChoice: boolean  // Show engine selector in UI
}
```

**UI Controls**:
- Settings: Default compilation engine
- Per-compilation: Dropdown in compile button (Advanced users)
- Status: Show which engine was used
- Fallback notification: "WASM compilation failed, using server..."

**Benefits**:
- ✅ Power users can force Docker for reliability
- ✅ Users on fast connections can choose WASM
- ✅ Mobile users default to Docker
- ✅ Testing: Users can compare WASM vs Docker results
- ✅ Package issues: If WASM lacks packages, user can switch to Docker

---

#### **SwiftLaTeX WASM Implementation**

**Frontend Integration**:
```typescript
// src/services/compiler-wasm.ts
import { SwiftLaTeX } from 'swiftlatex';

class WasmCompiler {
  private engine: SwiftLaTeX;
  
  async initialize() {
    // Load WASM engine (~30MB initial download, cached)
    this.engine = await SwiftLaTeX.load();
    
    // Load common LaTeX packages
    await this.engine.loadPackages([
      'latex-base',
      'amsmath',
      'graphicx',
      'hyperref'
    ]);
  }
  
  async compile(files: Map<string, string>): Promise<Uint8Array> {
    // Set up virtual file system
    for (const [path, content] of files) {
      this.engine.writeFile(path, content);
    }
    
    // Compile (runs entirely in browser)
    const result = await this.engine.compile('main.tex', {
      timeout: 30000,  // 30 seconds
      maxMemory: 512   // MB
    });
    
    if (result.status === 'success') {
      return result.pdf;  // Uint8Array
    } else {
      throw new CompilationError(result.log);
    }
  }
  
  isSupported(): boolean {
    // Check browser capabilities
    return typeof WebAssembly !== 'undefined' 
      && navigator.hardwareConcurrency >= 2
      && performance.memory?.jsHeapSizeLimit > 4 * 1024 * 1024 * 1024;
  }
}
```

**User Experience**:
```typescript
async function compileDocument() {
  // Try WASM first (if supported)
  if (wasmCompiler.isSupported()) {
    try {
      showStatus('Compiling locally...');
      const pdf = await wasmCompiler.compile(files);
      showPDF(pdf);
      return;
    } catch (error) {
      console.warn('WASM compilation failed, falling back to server', error);
    }
  }
  
  // Fallback to server compilation
  showStatus('Compiling on server...');
  const pdf = await serverCompiler.compile(files);
  showPDF(pdf);
}
```

---

#### **Server-Side Docker Compilation**

**Approach**:
- Ephemeral containers for each compilation
- Base image: `texlive/texlive:latest` or custom image
- Isolated file system for security
- Resource limits (CPU, memory, timeout)
- Compilation artifacts stored in MinIO

**When to use**:
- Mobile devices
- Browsers without WASM support
- Low-memory clients (<4GB)
- SwiftLaTeX package not available
- Complex documents requiring full TeXLive
- User preference (settings)

**Security Measures**:
- No network access from compilation containers
- Read-only LaTeX packages
- User files mounted as volumes
- Automatic cleanup after compilation
- Shell command restrictions
- seccomp profiles

**Workflow**:
1. User triggers compilation
2. Check if WASM failed or unavailable
3. Compiler service fetches files from MinIO
4. Spins up Docker container with timeout
5. Runs LaTeX compilation
6. Stores PDF and logs in MinIO
7. Returns result to user
8. Container destroyed

---

#### **Compilation Service Architecture**

**Go Compiler Service**:
```go
// cmd/compiler/main.go
type CompilationRequest struct {
    ProjectID   string
    Files       []string
    Engine      string  // "wasm" | "docker" | "auto"
    Priority    int     // Express lane for WASM fallbacks
}

func (s *CompilerService) Compile(req CompilationRequest) (*PDF, error) {
    // If WASM is requested, client handles it
    if req.Engine == "wasm" {
        return nil, errors.New("WASM compilation handled by client")
    }
    
    // Server-side Docker compilation
    return s.compileDocker(req)
}

func (s *CompilerService) compileDocker(req CompilationRequest) (*PDF, error) {
    // 1. Fetch files from MinIO
    files := s.fetchFiles(req.ProjectID, req.Files)
    
    // 2. Create temporary directory
    tmpDir := s.createTempDir()
    defer os.RemoveAll(tmpDir)
    
    // 3. Write files
    for path, content := range files {
        ioutil.WriteFile(filepath.Join(tmpDir, path), content, 0644)
    }
    
    // 4. Spin up Docker container
    ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
    defer cancel()
    
    containerID := s.docker.Run(ctx, &docker.RunOptions{
        Image: "texlive/texlive:latest",
        Volumes: []string{tmpDir + ":/workspace:ro"},
        Memory: "2g",
        CPUs: 1,
        NetworkMode: "none",  // No network access
        ReadOnly: true,       // Read-only root filesystem
        SecurityOpt: []string{"seccomp=latex-seccomp.json"},
    })
    
    // 5. Run compilation
    output, err := s.docker.Exec(ctx, containerID, []string{
        "pdflatex", 
        "-interaction=nonstopmode",
        "-output-directory=/workspace",
        "/workspace/main.tex",
    })
    
    // 6. Read PDF
    pdfPath := filepath.Join(tmpDir, "main.pdf")
    pdf, err := ioutil.ReadFile(pdfPath)
    
    // 7. Store in MinIO
    s.minio.PutObject(req.ProjectID + "/output/main.pdf", pdf)
    s.minio.PutObject(req.ProjectID + "/output/compile.log", output)
    
    // 8. Cleanup container
    s.docker.Remove(containerID)
    
    return &PDF{Data: pdf, Log: output}, nil
}
```

---

#### **Compilation Comparison**

| Feature | SwiftLaTeX WASM | Docker TeXLive |
|---------|----------------|----------------|
| **Speed** | <2 seconds | 5-15 seconds |
| **Package Support** | Common packages | All packages |
| **Server Load** | Zero | High |
| **Cost** | Free | CPU/memory cost |
| **Offline** | Yes | No |
| **Queue** | No queue | May queue |
| **Complex Docs** | Limited | Full support |
| **Mobile** | No | Yes |

---

#### **Implementation Strategy**

**Phase 1**: Server-side Docker only (MVP)
- Get basic compilation working
- Establish infrastructure

**Phase 2**: Add SwiftLaTeX WASM
- Integrate WASM engine
- Auto-detect capability
- Fallback to Docker

**Phase 3**: Smart routing
- Track which documents compile successfully in WASM
- Auto-route simple documents to WASM
- Auto-route complex documents to Docker
- User can override in settings

---

#### **User Settings**

```javascript
// MongoDB: users.settings.compilation
{
  preferredEngine: "auto",  // "auto" | "wasm" | "docker"
  wasmEnabled: true,
  fallbackToDocker: true,
  dockerPriority: "normal"  // "express" | "normal" | "background"
}
```

**UI Toggle**:
```
Compilation Settings:
[ ] Compile locally in browser (faster, recommended)
[x] Fallback to server if needed
Preferred engine: [ Auto ▼ ]
```

---

#### **Cost Savings with WASM**

Assuming 1000 users, 10 compilations/day each:
- **Without WASM**: 10,000 Docker compilations/day
  - ~10 seconds each = 27.7 hours CPU time
  - Cost: ~$50-100/day in cloud compute
  
- **With WASM** (80% handled by client):
  - 2,000 Docker compilations/day
  - Cost: ~$10-20/day
  - **Savings**: $40-80/day = $1,200-2,400/month

WASM is a huge win! 🎉

---

## Potential Issues & Mitigations

### 1. **Real-time Sync Latency**
- **Issue**: Users on slow connections may see lag
- **Mitigation**: Optimistic updates, connection quality indicator, Yjs handles network issues gracefully

### 2. **LaTeX Compilation Time**
- **Issue**: Large documents take time to compile
- **Mitigation**: Incremental compilation, cache intermediate files, queue system with priority

### 3. **Concurrent Editing Conflicts**
- **Issue**: Two users editing same line simultaneously
- **Mitigation**: Yjs handles this automatically, show user cursors to avoid conflicts

### 4. **Docker Security**
- **Issue**: Malicious LaTeX code could exploit compilation
- **Mitigation**: Read-only packages, no network, CPU/memory limits, timeout, seccomp profiles

### 5. **Storage Costs**
- **Issue**: Many versions and PDFs consume storage
- **Mitigation**: Lifecycle policies, compress old versions, user quotas

### 6. **WebSocket Connection Limits**
- **Issue**: Too many concurrent connections
- **Mitigation**: Horizontal scaling with Redis pub/sub, connection pooling

---

## Alternative Tech Considerations

### Alternative Databases
- **PostgreSQL**: Better for relational data, ACID compliance
  - **When to consider**: If you need complex queries or strict consistency
- **Current choice justified**: MongoDB's flexibility is better for evolving schema

### Alternative to Monaco Editor

**Primary Options for LaTeX Editing**:

#### **Option 1: Monaco Editor** (Current choice)
- **What**: VS Code's editor component
- **Used by**: VS Code, GitHub Codespaces, StackBlitz
- **Size**: ~2.5MB (minified)
- **License**: MIT

**Pros**:
- ✅ Extremely feature-rich out of the box
- ✅ IntelliSense/autocomplete built-in
- ✅ Multi-cursor support
- ✅ Find/replace with regex
- ✅ Minimap, breadcrumbs, folding
- ✅ VS Code-like UI (matches our goal)
- ✅ Excellent TypeScript support
- ✅ `y-monaco` binding for Yjs collaboration
- ✅ Mature, actively maintained by Microsoft
- ✅ LaTeX language support via extensions
- ✅ Diff editor (perfect for change tracking)

**Cons**:
- ❌ Large bundle size (2.5MB)
- ❌ Heavy on initial load
- ❌ Less customizable theming
- ❌ Not designed for mobile
- ❌ Opinionated about features

**Best for**: Feature-rich desktop application, VS Code-like experience

---

#### **Option 2: CodeMirror 6** ✅ **SELECTED**
- **What**: Modern, modular code editor
- **Used by**: Replit, Observable, MDN Docs
- **Size**: ~200KB (core) + extensions
- **License**: MIT

**Pros**:
- ✅ Lightweight and fast
- ✅ Highly modular (add only what you need)
- ✅ **Excellent mobile support** (critical for our requirement)
- ✅ Tree-based document model (efficient)
- ✅ Better performance on large files
- ✅ `y-codemirror.next` binding for Yjs
- ✅ Full theme customization
- ✅ LaTeX mode available (`@codemirror/lang-latex`)
- ✅ Smaller bundle = faster load
- ✅ Better for embedding in complex UIs
- ✅ **Touch-friendly** (mobile editing)

**Cons** (acceptable trade-offs):
- ⚠️ Less features out of the box (we'll build what we need)
- ⚠️ More work to implement advanced features (worth it for mobile)
- ⚠️ Smaller ecosystem than Monaco (sufficient for our needs)
- ⚠️ Not VS Code-like (we can theme it similarly)
- ⚠️ Less polished IntelliSense (acceptable for LaTeX)

**Best for**: Performance-critical apps, **mobile support**, custom UIs

**Why Selected**:
- Mobile support is a requirement (CodeMirror 6 excels here)
- Lighter bundle size benefits all users
- Customizable enough to achieve VS Code-like aesthetic
- Excellent Yjs integration (`y-codemirror.next`)
- Better performance on mobile devices

---

#### **Option 3: Ace Editor**
- **What**: Older, mature code editor
- **Used by**: Cloud9, GitHub, Khan Academy
- **Size**: ~500KB
- **License**: BSD

**Pros**:
- ✅ Battle-tested, very stable
- ✅ LaTeX mode built-in
- ✅ Good performance
- ✅ Many themes available

**Cons**:
- ❌ Aging codebase (less active development)
- ❌ No official Yjs binding (would need custom)
- ❌ Less modern architecture
- ❌ Not as feature-rich as Monaco

**Best for**: Legacy projects, stable environments

---

#### **Option 4: ProseMirror** (with code extensions)
- **What**: Rich text editor framework
- **Used by**: Notion, Dropbox Paper, Atlassian
- **Size**: ~300KB + plugins
- **License**: MIT

**Pros**:
- ✅ WYSIWYG potential (render LaTeX inline)
- ✅ Excellent collaborative editing (built for it)
- ✅ `y-prosemirror` binding (first-class Yjs support)
- ✅ Schema-based (structured documents)
- ✅ Track changes built into architecture

**Cons**:
- ❌ Not designed for code editing
- ❌ Would need custom LaTeX syntax highlighting
- ❌ No code features (folding, etc.)
- ❌ Complex to set up for code

**Best for**: Rich text + LaTeX hybrid (math equations inline)

---

#### **Option 5: Custom Editor on Textarea** (with libraries)
- Textarea + syntax highlighting library (e.g., Prism.js)
- **Size**: <100KB
- **License**: Various

**Pros**:
- ✅ Extremely lightweight
- ✅ Full control
- ✅ Simple to understand

**Cons**:
- ❌ Would need to build all features from scratch
- ❌ Poor user experience
- ❌ Not recommended for serious projects

---

### **Detailed Comparison for Our Use Case**

| Feature | Monaco | CodeMirror 6 | Ace | ProseMirror |
|---------|--------|--------------|-----|-------------|
| **Bundle Size** | 2.5MB | 200KB+ | 500KB | 300KB+ |
| **Yjs Integration** | ⭐⭐⭐ | ⭐⭐⭐ | ❌ | ⭐⭐⭐⭐ |
| **LaTeX Support** | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| **VS Code Feel** | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐ | ⭐ |
| **Performance** | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| **Mobile** | ⭐ | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| **Customization** | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Features** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| **Diff View** | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐ | ❌ |
| **Maintenance** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |

---

### **Editor Decision**

**PRIMARY CHOICE: CodeMirror 6** ✅

**Why CodeMirror 6**:
1. **Mobile support requirement**: CodeMirror 6 is touch-friendly and mobile-optimized
2. **Lightweight**: ~200KB vs Monaco's 2.5MB (10x smaller, faster load on mobile)
3. **Performance**: Better on mobile devices and large files
4. **Yjs integration**: Excellent `y-codemirror.next` bindings
5. **Customizable**: Can achieve VS Code-like aesthetic with custom theme
6. **Modular**: Add only what we need (LaTeX-specific features)

**Key Libraries**:
```typescript
// Core
import { EditorView, basicSetup } from 'codemirror'
import { EditorState } from '@codemirror/state'

// LaTeX support
import { StreamLanguage } from '@codemirror/language'
import { stex } from '@codemirror/legacy-modes/mode/stex'

// Yjs collaboration
import { yCollab } from 'y-codemirror.next'

// Theme (VS Code-like)
import { oneDark } from '@codemirror/theme-one-dark'

// Mobile optimizations
import { drawSelection, keymap } from '@codemirror/view'
```

**Features to Implement**:
- ✅ LaTeX syntax highlighting
- ✅ Autocomplete (LaTeX commands, citations, labels)
- ✅ Line numbers, folding
- ✅ Search/replace
- ✅ Multi-cursor (limited on mobile, full on desktop)
- ✅ Real-time collaboration cursors
- ✅ Touch gestures (mobile)
- ✅ Diff view (for change tracking)

**Mobile Optimizations**:
- Touch-friendly selection handles
- Virtual keyboard support
- Pinch-to-zoom (optional)
- Swipe gestures for navigation
- Simplified toolbar for mobile
- Bottom action bar (easier thumb access)

**Desktop Features**:
- Full keyboard shortcuts
- Multiple cursors
- Advanced find/replace
- Command palette
- Minimap (optional extension)

**Trade-offs Accepted**:
- Need to build some features from scratch (vs Monaco's built-ins)
- Custom LaTeX IntelliSense implementation
- Diff editor requires custom implementation

**Why Not Monaco**:
- ❌ Poor mobile support (not designed for touch)
- ❌ Large bundle size (slow on mobile networks)
- ❌ Resource-heavy (struggles on low-end mobile devices)
- ❌ No mobile-friendly keyboard handling

**Implementation Plan**:
1. Phase 1: Basic CodeMirror 6 setup with LaTeX mode
2. Phase 2: Yjs integration for collaboration
3. Phase 3: Mobile optimizations (touch, gestures)
4. Phase 4: Advanced features (autocomplete, diff view)
5. Phase 5: VS Code-inspired theming

### Alternative Real-time Frameworks
- **Socket.io**: Higher-level than `ws`, auto-reconnection
  - **Trade-off**: More overhead, but easier to use
- **Recommendation**: Start with Socket.io for development speed

### Alternative to Docker for Compilation
- **Sandboxed processes**: gVisor, Firecracker
  - **When to consider**: If Docker overhead is too high
- **Current choice justified**: Docker is simpler and well-understood

---

## Docker Orchestration

**Based on existing gogolatex_docker architecture** ✅

Your existing Docker orchestration from `gogolatex_docker` provides an excellent foundation. We'll reuse and extend it.

### **Architecture Pattern from gogolatex_docker**

**Key Principles** (maintaining your approach):
1. ✅ **External network**: `gogolagogolatex-network` (isolated, secure)
2. ✅ **Modular compose files**: Each service in its own directory with `compose.yaml`
3. ✅ **Management scripts**: Simple `up_*.sh`, `down_*.sh`, `logs_*.sh`, `exec_*.sh` scripts
4. ✅ **Health checks**: All services have proper health checks
5. ✅ **Named containers**: `gogolatex-*` prefix for easy identification
6. ✅ **Volume persistence**: Local volumes for data persistence
7. ✅ **Environment variables**: `.env` file for configuration

### **Directory Structure** (extending your pattern)

```
gogotex/
├── .env                           # Environment variables
├── .env_sample                    # Sample configuration
├── compose.yaml                   # Main compose (extends all services)
├── make_docker_tex_network.sh    # Network setup (reuse yours)
│
├── mongodb/
│   ├── compose.yaml               # MongoDB service (reuse yours)
│   ├── data_db/                   # Volume
│   ├── data_configdb/             # Volume
│   ├── backup/                    # Volume
│   └── mongo-init/                # Initialization scripts
│
├── redis/
│   ├── compose.yaml               # Redis service (reuse yours)
│   └── data/                      # Volume
│
├── minio/
│   ├── compose.yaml               # MinIO service (reuse yours)
│   └── data/                      # Volume
│
├── yjs-server/                    # Node.js real-time (extend yours)
│   ├── compose.yaml               # Yjs server config
│   ├── Dockerfile
│   ├── package.json
│   ├── src/
│   │   ├── server.ts
│   │   ├── yjs-handler.ts
│   │   ├── redis-persistence.ts
│   │   └── minio-sync.ts
│   └── logs/                      # Volume
│
├── go-services/                   # NEW: Go backend services
│   ├── compose.yaml
│   ├── Dockerfile
│   ├── go.mod
│   ├── cmd/
│   │   ├── auth/
│   │   ├── document/
│   │   └── compiler/
│   └── internal/
│
├── frontend/                      # Extend your gogolatex-frontend
│   ├── compose.yaml
│   ├── Dockerfile
│   ├── package.json
│   └── src/
│
├── latex-compiler-worker/         # NEW: Docker LaTeX compilation
│   ├── compose.yaml
│   ├── Dockerfile                 # TeXLive base
│   └── sandbox-config/
│
├── keycloak/                      # NEW: Authentication
│   ├── compose.yaml
│   └── data/                      # Volume
│
├── mongo-express/                 # Admin UI (reuse yours)
│   └── compose.yaml
│
├── redis-commander/               # Admin UI (reuse yours)
│   └── compose.yaml
│
└── scripts/                       # Management scripts (your pattern)
    ├── up_*.sh                    # Start individual services
    ├── down_*.sh                  # Stop individual services
    ├── logs_*.sh                  # View logs
    ├── exec_*.sh                  # Exec into containers
    ├── up_all.sh                  # Start everything
    └── down_all.sh                # Stop everything
```

### **Main compose.yaml** (extending your pattern)

```yaml
services:

  # Core infrastructure (reuse from gogolatex_docker)
  mongodb:
    extends:
      file: ./mongodb/compose.yaml
      service: mongodb

  redis:
    extends:
      file: ./redis/compose.yaml
      service: redis

  minio:
    extends:
      file: ./minio/compose.yaml
      service: minio

  # Admin UIs (reuse from gogolatex_docker)
  mongo-express:
    extends:
      file: ./mongo-express/compose.yaml
      service: mongo-express
    depends_on:
      mongodb:
        condition: service_healthy

  redis-commander:
    extends:
      file: ./redis-commander/compose.yaml
      service: redis-commander
    depends_on:
      redis:
        condition: service_healthy

  # Authentication (NEW)
  keycloak:
    extends:
      file: ./keycloak/compose.yaml
      service: keycloak
    depends_on:
      mongodb:
        condition: service_healthy

  # Go backend services (NEW)
  go-auth:
    extends:
      file: ./go-services/compose.yaml
      service: go-auth
    depends_on:
      keycloak:
        condition: service_healthy
      mongodb:
        condition: service_healthy
      redis:
        condition: service_healthy

  go-document:
    extends:
      file: ./go-services/compose.yaml
      service: go-document
    depends_on:
      mongodb:
        condition: service_healthy
      minio:
        condition: service_healthy
      redis:
        condition: service_healthy

  go-compiler:
    extends:
      file: ./go-services/compose.yaml
      service: go-compiler
    depends_on:
      redis:
        condition: service_healthy
      minio:
        condition: service_healthy

  # LaTeX compiler workers (NEW)
  latex-worker:
    extends:
      file: ./latex-compiler-worker/compose.yaml
      service: latex-worker
    deploy:
      replicas: 3  # Multiple workers
    depends_on:
      redis:
        condition: service_healthy
      minio:
        condition: service_healthy

  # Real-time collaboration (extend yours)
  yjs-server:
    extends:
      file: ./yjs-server/compose.yaml
      service: yjs-server
    build:
      context: ./yjs-server
    depends_on:
      mongodb:
        condition: service_healthy
      redis:
        condition: service_healthy
      minio:
        condition: service_healthy

  # Frontend (extend yours)
  frontend:
    extends:
      file: ./frontend/compose.yaml
      service: frontend
    build:
      context: ./frontend
    depends_on:
      yjs-server:
        condition: service_healthy
      minio:
        condition: service_healthy
      go-auth:
        condition: service_healthy

networks:
  gogolatex-network:
    external: true
```

### **MongoDB Service** (reuse yours with minor updates)

```yaml
# mongodb/compose.yaml (your configuration works great!)
services:
  mongodb:
    image: "mongo:8.0"
    container_name: gogolatex-mongodb
    hostname: gogolatex-mongodb
    restart: always
    healthcheck:
      test: "mongosh --quiet --eval 'rs.hello().setName ? rs.hello().setName : rs.initiate({_id: \"texlyre\",members:[{_id: 0, host:\"gogolatex-mongodb:27017\"}]})'"
      interval: 10s
      timeout: 10s
      retries: 5
    command: "--replSet texlyre"
    volumes:
      - ./data_db:/data/db
      - ./data_configdb:/data/configdb
      - ./backup:/backup
      - ./mongo-init:/docker-entrypoint-initdb.d:ro
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - gogolatex-network
    expose: 
      - 27017
    environment:
      - MONGO_INITDB_DATABASE=gogolatex

networks:
  gogolatex-network:
    external: true
```

### **Redis Service** (reuse yours)

```yaml
# redis/compose.yaml (perfect as-is!)
services:
  redis:
    image: "redis:8.4-alpine"
    container_name: gogolatex-redis
    hostname: gogolatex-redis
    restart: always
    healthcheck:
      test: ["CMD-SHELL", "redis-cli ping | grep PONG"]
      start_period: 20s
      interval: 30s
      retries: 5
      timeout: 3s
    command: --save 60 1 --loglevel warning
    volumes:
      - ./data:/data
      - /var/run/docker.sock:/var/run/docker.sock
    expose:
      - 6379
    networks:
      - gogolatex-network
    environment:
      REDIS_AOF_PERSISTENCE: "true"

networks:
  gogolatex-network:
    external: true
```

### **MinIO Service** (reuse yours)

```yaml
# minio/compose.yaml (works well!)
services:
  minio:
    image: minio/minio:latest
    container_name: gogolatex-minio
    hostname: gogolatex-minio
    restart: always
    ports:
      - "9000:9000"   # API
      - "9001:9001"   # Console (Web UI)
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:-admin}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD:-changeme123}
    command: server /data --console-address ":9001"
    volumes:
      - ./data:/data
    networks:
      - gogolatex-network
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 30s
      timeout: 20s
      retries: 3

networks:
  gogolatex-network:
    external: true
```

### **Yjs Server** (extend yours with MinIO sync)

```yaml
# yjs-server/compose.yaml (enhanced from yours)
services:
  yjs-server:
    build: .
    container_name: gogolatex-yjs-server
    hostname: gogolatex-yjs-server
    restart: always
    ports:
      - "4444:1234"
    environment:
      - MONGODB_URI=mongodb://gogolatex-mongodb:27017/texlyre?replicaSet=gogolatex
      - REDIS_URL=redis://gogolatex-redis:6379
      - MINIO_ENDPOINT=gogolatex-minio:9000
      - MINIO_ACCESS_KEY=${MINIO_ROOT_USER:-admin}
      - MINIO_SECRET_KEY=${MINIO_ROOT_PASSWORD:-changeme123}
      - WS_PORT=1234
      - NODE_ENV=production
      - REDIS_CACHE_ENABLED=true
      - REDIS_CACHE_TTL=604800  # 7 days (for Yjs state)
      - MINIO_SYNC_INTERVAL=300000  # 5 minutes
      - MINIO_SYNC_UPDATES=100      # or 100 updates
    networks:
      - gogolatex-network
    volumes:
      - ./logs:/app/logs
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:1234/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  gogolatex-network:
    external: true
```

### **Go Services** (NEW)

```yaml
# go-services/compose.yaml
services:
  go-auth:
    build:
      context: .
      target: auth
    container_name: gogolatex-go-auth
    hostname: gogolatex-go-auth
    restart: always
    ports:
      - "8001:8001"
    environment:
      - PORT=8001
      - KEYCLOAK_URL=http://gogolatex-keycloak:8080
      - KEYCLOAK_REALM=gogolatex
      - KEYCLOAK_CLIENT_ID=gogolatex-backend
      - KEYCLOAK_CLIENT_SECRET=${KEYCLOAK_CLIENT_SECRET}
      - MONGODB_URI=mongodb://gogolatex-mongodb:27017/texlyre?replicaSet=gogolatex
      - REDIS_URL=redis://gogolatex-redis:6379
      - JWT_SECRET=${JWT_SECRET}
    networks:
      - gogolatex-network
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8001/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  go-document:
    build:
      context: .
      target: document
    container_name: gogolatex-go-document
    hostname: gogolatex-go-document
    restart: always
    ports:
      - "8002:8002"
    environment:
      - PORT=8002
      - MONGODB_URI=mongodb://gogolatex-mongodb:27017/texlyre?replicaSet=gogolatex
      - REDIS_URL=redis://gogolatex-redis:6379
      - MINIO_ENDPOINT=gogolatex-minio:9000
      - MINIO_ACCESS_KEY=${MINIO_ROOT_USER:-admin}
      - MINIO_SECRET_KEY=${MINIO_ROOT_PASSWORD:-changeme123}
      - JWT_SECRET=${JWT_SECRET}
    networks:
      - gogolatex-network
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8002/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  go-compiler:
    build:
      context: .
      target: compiler
    container_name: gogolatex-go-compiler
    hostname: gogolatex-go-compiler
    restart: always
    ports:
      - "8003:8003"
    environment:
      - PORT=8003
      - REDIS_URL=redis://gogolatex-redis:6379
      - MINIO_ENDPOINT=gogolatex-minio:9000
      - MINIO_ACCESS_KEY=${MINIO_ROOT_USER:-admin}
      - MINIO_SECRET_KEY=${MINIO_ROOT_PASSWORD:-changeme123}
      - DOCKER_HOST=unix:///var/run/docker.sock
      - WORKER_COUNT=3
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - gogolatex-network
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8003/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  gogolatex-network:
    external: true
```

### **LaTeX Compiler Worker** (NEW)

```yaml
# latex-compiler-worker/compose.yaml
services:
  latex-worker:
    build: .
    image: gogolatex-latex-worker:latest
    restart: always
    environment:
      - REDIS_URL=redis://gogolatex-redis:6379
      - MINIO_ENDPOINT=gogolatex-minio:9000
      - MINIO_ACCESS_KEY=${MINIO_ROOT_USER:-admin}
      - MINIO_SECRET_KEY=${MINIO_ROOT_PASSWORD:-changeme123}
      - WORKER_ID=${HOSTNAME}
      - MAX_COMPILE_TIME=60
      - MAX_MEMORY=2g
    networks:
      - gogolatex-network
    volumes:
      - /tmp/latex-compile:/tmp/compile
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true

networks:
  gogolatex-network:
    external: true
```

### **Management Scripts** (your pattern)

```bash
# scripts/up_mongodb.sh (reuse yours)
#!/bin/bash
docker compose up -d mongodb

# scripts/down_mongodb.sh (reuse yours)
#!/bin/bash
docker compose down mongodb

# scripts/logs_mongodb.sh (reuse yours)
#!/bin/bash
docker logs -f gogolatex-mongodb

# scripts/exec_mongodb.sh (reuse yours)
#!/bin/bash
docker exec -it gogolatex-mongodb mongosh

# scripts/up_all.sh (NEW - starts everything in order)
#!/bin/bash
set -e

echo "Starting infrastructure..."
./scripts/up_mongodb.sh
./scripts/up_redis.sh
./scripts/up_minio.sh

echo "Waiting for infrastructure..."
sleep 10

echo "Starting authentication..."
./scripts/up_keycloak.sh

echo "Waiting for auth..."
sleep 5

echo "Starting backend services..."
./scripts/up_go-services.sh
./scripts/up_yjs-server.sh
./scripts/up_latex-worker.sh

echo "Starting frontend..."
./scripts/up_frontend.sh

echo "Starting admin UIs..."
./scripts/up_mongo-express.sh
./scripts/up_redis-commander.sh

echo "All services started!"
docker compose ps

# scripts/down_all.sh (NEW - stops everything)
#!/bin/bash
docker compose down

# scripts/logs_all.sh (NEW - tail all logs)
#!/bin/bash
docker compose logs -f
```

### **.env Configuration** (extending yours)

```bash
# .env (based on your .env_sample)

# MongoDB
MONGO_INITDB_DATABASE=gogolatex

# MinIO
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=changeme123

# Mongo Express (Admin UI)
MONGOEXPRESS_LOGIN=admin
MONGOEXPRESS_PASSWORD=changeme123

# Redis Commander (Admin UI)
REDIS_COMMANDER_USER=admin
REDIS_COMMANDER_PASSWORD=changeme123

# Keycloak
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=changeme123
KEYCLOAK_CLIENT_SECRET=your-secret-here

# JWT
JWT_SECRET=your-jwt-secret-here

# Frontend
VITE_WS_URL=ws://localhost:4444
VITE_API_URL=http://localhost:8080
VITE_AUTH_URL=http://localhost:8080/auth
VITE_STORAGE_MODE=hybrid
```

### **Network Setup** (reuse your script)

```bash
# make_docker_tex_network.sh (your script is excellent!)
#!/bin/bash
docker network create gogolatex-network
snetz=`docker network inspect gogolatex-network | grep "Subnet" | sed s/" "/""/g | sed s/"\,"/""/g | sed s/":"/"\n"/g | grep -v "Subnet" | sed s/'"'/''/g | grep -v "\{"`
nid=`docker network ls | grep gogolatex-network | awk '{print $1}'`

ufw allow in on br-$nid
ufw route allow in on br-$nid
ufw route allow out on br-$nid
iptables -t nat -A POSTROUTING ! -o br-$nid -s $snetz -j MASQUERADE
```

### **Key Improvements from Your Architecture**

Your gogolatex_docker architecture is excellent! We're maintaining:

1. ✅ **Modular compose files** - Each service self-contained
2. ✅ **External network** - Security isolation
3. ✅ **Health checks** - Proper dependency management
4. ✅ **Management scripts** - Simple operations
5. ✅ **Volume persistence** - Data safety
6. ✅ **Environment variables** - Easy configuration

**New additions**:
- Keycloak for authentication
- Go backend services (auth, document, compiler)
- LaTeX worker pool
- Enhanced Yjs server with MinIO sync

This maintains your proven patterns while adding the new capabilities we need! 🎯

---

## Development Phases

### Phase 1: Core Infrastructure (4-6 weeks)
- [ ] Set up development environment (Docker Compose)
- [ ] Go Auth Service + Keycloak integration
- [ ] Basic MongoDB schemas
- [ ] MinIO setup
- [ ] Basic React frontend with Monaco Editor
- [ ] Simple LaTeX compilation service

### Phase 2: Real-time Collaboration (6-8 weeks)
- [ ] Node.js WebSocket server
- [ ] Yjs integration
- [ ] Multi-user editing
- [ ] Cursor presence
- [ ] Real-time chat

### Phase 3: LaTeX Features (4-6 weeks)
- [ ] PDF preview
- [ ] Syntax highlighting
- [ ] Auto-completion
- [ ] Error navigation
- [ ] Package management

### Phase 4: Collaboration Features (6-8 weeks)
- [ ] Comments system
- [ ] Change tracking
- [ ] Accept/reject changes
- [ ] User permissions

### Phase 5: Git Integration (4-6 weeks)
- [ ] Git sync service
- [ ] Import from Git
- [ ] Export to Git
- [ ] Basic branch support

### Phase 6: Polish & Scale (4-6 weeks)
- [ ] Performance optimization
- [ ] Horizontal scaling
- [ ] Security hardening
- [ ] UI/UX improvements
- [ ] Documentation

---

## Plugin/Extension Architecture

**CRITICAL DESIGN DECISION**: Plan for extensibility from day one

Future features identified:
1. **AI Assistance** (writing, grammar, LaTeX code generation)
2. **BibTeX Importer/Editor** (reference management)
3. **Citation Manager** (add citations from reference managers)
4. **Equation Editor** (visual LaTeX math editor)
5. **Template Gallery**
6. **Spell/Grammar Check**
7. **Diagram/Drawing Tools** (TikZ helper)

### **Plugin Architecture Design**

#### **Core System + Plugin Model**

```
Core Application:
- Document editing (Monaco + Yjs)
- User authentication
- Real-time collaboration
- LaTeX compilation
- Project management

Plugins:
- Extended functionality
- Sandboxed execution
- API access via plugin interface
- UI integration points
```

#### **Plugin Types**

**1. Editor Extensions** (Frontend)
- Extend Monaco Editor functionality
- Add commands, menus, shortcuts
- Access document content (read/write via API)
- Examples: AI assistant, equation editor, snippets

**2. Service Plugins** (Backend)
- Extend Go/Node.js services
- Add REST endpoints
- Background processing
- Examples: BibTeX processor, grammar checker

**3. UI Widgets** (Frontend)
- Add panels, sidebars, dialogs
- React components
- Access to application context
- Examples: Citation manager, template browser

**4. Compilation Hooks** (Backend)
- Pre/post compilation processing
- Modify compilation pipeline
- Examples: Custom LaTeX packages, linting

---

### **Plugin Architecture Options**

**DESIGN PRINCIPLE**: Plugins can have frontend and/or backend components ✅

All plugin options support dual-mode plugins:

#### **Option A: VS Code Extension Model (Adapted)**
Follow VS Code extension architecture (simplified)

```typescript
// Plugin manifest: plugin.json
{
  "id": "ai-assistant",
  "name": "AI LaTeX Assistant",
  "version": "1.0.0",
  "type": "hybrid",  // "frontend" | "backend" | "hybrid"
  
  // Frontend component (optional)
  "frontend": {
    "main": "dist/frontend.js",
    "activationEvents": ["onCommand:ai.complete"],
    "contributes": {
      "commands": [{
        "command": "ai.complete",
        "title": "AI Complete"
      }]
    }
  },
  
  // Backend component (optional)
  "backend": {
    "type": "docker",  // "docker" | "go-plugin" | "node-service"
    "image": "gogolatex-plugins/ai-assistant:1.0.0",
    "endpoints": [
      {"path": "/api/ai/complete", "method": "POST"}
    ],
    "resources": {
      "cpu": "500m",
      "memory": "512Mi"
    }
  }
}

// Frontend code: src/frontend/index.ts
export function activate(context: PluginContext) {
  context.registerCommand('ai.complete', async () => {
    const editor = context.getActiveEditor();
    const text = editor.getSelectedText();
    
    // Call backend component
    const response = await context.backend.call('/api/ai/complete', {
      text,
      context: editor.getText()
    });
    
    editor.insertText(response.completion);
  });
}

// Backend code: backend/main.go or backend/server.js
// Runs in Docker container, exposes REST API
```

**Pros**:
- ✅ Clear separation of frontend/backend
- ✅ Familiar to VS Code extension developers
- ✅ Well-designed API surface
- ✅ Sandboxed backend (Docker)

**Cons**:
- ⚠️ Complex to implement
- ⚠️ Heavy infrastructure

---

#### **Option B: Simple JavaScript + Backend Services** ✅ **RECOMMENDED**
Lightweight plugin loading with optional backend

```typescript
// Plugin interface
interface Plugin {
  id: string;
  name: string;
  version: string;
  type: "frontend" | "backend" | "hybrid";
  
  // Frontend component (optional)
  frontend?: {
    // Lifecycle hooks
    onLoad?(context: PluginContext): void;
    onActivate?(context: PluginContext): void;
    onDeactivate?(): void;
    
    // Feature contributions
    commands?: Command[];
    panels?: Panel[];
    menuItems?: MenuItem[];
  };
  
  // Backend component (optional)
  backend?: {
    type: "docker" | "go" | "node";
    config: BackendConfig;
  };
}

// Plugin context (API provided to frontend plugins)
interface PluginContext {
  // Editor access
  editor: {
    getText(): string;
    getSelection(): string;
    insertText(text: string): void;
    replaceSelection(text: string): void;
    decorateRange(range: Range, style: Style): void;
  };
  
  // Document access
  document: {
    getCurrentFile(): string;
    getProjectFiles(): string[];
    readFile(path: string): Promise<string>;
    writeFile(path: string, content: string): Promise<void>;
  };
  
  // UI
  ui: {
    showMessage(msg: string): void;
    showInputBox(prompt: string): Promise<string>;
    addPanel(panel: PanelConfig): Panel;
    addMenuItem(item: MenuItemConfig): void;
  };
  
  // HTTP client (for plugin backends)
  http: {
    get(url: string): Promise<Response>;
    post(url: string, data: any): Promise<Response>;
  };
  
  // Storage (plugin-specific)
  storage: {
    get(key: string): Promise<any>;
    set(key: string, value: any): Promise<void>;
  };
}
```

**Pros**:
- Simple to implement
- Easy for developers to create plugins
- Flexible

**Cons**:
- Less structured
- Need to design API carefully

---

#### **Option C: Web Components + IFrame Sandboxing**
Plugins as isolated web components

```typescript
// Plugin loaded in iframe
<iframe 
  src="/plugins/ai-assistant/index.html"
  sandbox="allow-scripts allow-same-origin"
  data-plugin-id="ai-assistant"
></iframe>

// Plugin communicates via postMessage
window.parent.postMessage({
  type: 'plugin:command',
  pluginId: 'ai-assistant',
  command: 'insertText',
  data: { text: 'Hello' }
}, '*');
```

**Pros**:
- True sandboxing (security)
- Plugin can't break main app
- Can use any framework

**Cons**:
- Communication overhead
- Complex setup
- Harder to integrate UI

---

### **Recommended Plugin Architecture**

**Hybrid Approach**: Simple JavaScript + Optional Backend Services

```
Frontend Plugins:
- Loaded as ES modules
- Access via PluginContext API (Option B)
- Hot-reload during development
- Installed from plugin marketplace

Backend Plugins (for complex features):
- Docker containers with REST API
- Register endpoints with main backend
- Isolated execution
- Examples: AI services, heavy processing
```

---

### **Plugin System Implementation**

#### **1. Plugin Discovery & Loading**

```typescript
// Core app: src/plugins/plugin-manager.ts
class PluginManager {
  private plugins: Map<string, Plugin> = new Map();
  
  async loadPlugin(pluginId: string) {
    // Fetch plugin from marketplace or local
    const manifest = await fetch(`/plugins/${pluginId}/plugin.json`);
    const code = await fetch(`/plugins/${pluginId}/index.js`);
    
    // Create sandbox context
    const context = this.createPluginContext(pluginId);
    
    // Execute plugin code
    const module = await import(code.url);
    const plugin = module.default;
    
    // Activate plugin
    if (plugin.onActivate) {
      plugin.onActivate(context);
    }
    
    this.plugins.set(pluginId, plugin);
  }
  
  private createPluginContext(pluginId: string): PluginContext {
    return {
      editor: this.createEditorAPI(),
      document: this.createDocumentAPI(),
      ui: this.createUIAPI(),
      http: this.createHTTPAPI(),
      storage: this.createStorageAPI(pluginId)
    };
  }
}
```

#### **2. Plugin Storage**

**MongoDB**:
```javascript
// Collection: plugins
{
  _id: ObjectId,
  pluginId: "ai-assistant",
  name: "AI LaTeX Assistant",
  version: "1.0.0",
  author: "John Doe",
  description: "AI-powered LaTeX completion",
  type: "editor-extension",
  
  // Plugin files
  files: {
    manifest: "plugin.json",
    entrypoint: "dist/index.js",
    assets: ["icon.png"]
  },
  
  // Marketplace metadata
  downloads: 1234,
  rating: 4.5,
  verified: true,
  
  // Installation
  installedBy: [ObjectId],  // User IDs
  
  // Backend service (if needed)
  service: {
    dockerImage: "plugins/ai-assistant:1.0.0",
    endpoint: "/api/plugins/ai-assistant",
    resources: {
      cpu: "500m",
      memory: "512Mi"
    }
  }
}

// Collection: user_plugins (per-user installed plugins)
{
  _id: ObjectId,
  userId: ObjectId,
  pluginId: "ai-assistant",
  enabled: true,
  settings: {
    apiKey: "...",
    model: "gpt-4"
  }
}
```

**MinIO**:
```
plugins/
├── ai-assistant/
│   ├── 1.0.0/
│   │   ├── plugin.json
│   │   ├── dist/
│   │   │   └── index.js
│   │   └── assets/
│   │       └── icon.png
│   └── 1.0.1/
├── bibtex-editor/
└── equation-editor/
```

#### **3. Plugin API Examples**

**AI Assistant Plugin**:
```typescript
// plugins/ai-assistant/src/index.ts
export default {
  id: 'ai-assistant',
  name: 'AI LaTeX Assistant',
  version: '1.0.0',
  
  onActivate(context: PluginContext) {
    // Add command
    context.registerCommand('ai.complete', async () => {
      const selection = context.editor.getSelection();
      
      // Call plugin backend service
      const response = await context.http.post('/api/plugins/ai-assistant/complete', {
        text: selection,
        context: context.editor.getText()
      });
      
      const completion = await response.json();
      context.editor.replaceSelection(completion.text);
    });
    
    // Add menu item
    context.ui.addMenuItem({
      id: 'ai.complete',
      label: 'AI Complete',
      command: 'ai.complete',
      keybinding: 'Ctrl+Shift+A'
    });
    
    // Add panel
    context.ui.addPanel({
      id: 'ai-chat',
      title: 'AI Chat',
      position: 'right',
      component: AIChatPanel  // React component
    });
  }
};
```

**BibTeX Editor Plugin**:
```typescript
// plugins/bibtex-editor/src/index.ts
export default {
  id: 'bibtex-editor',
  name: 'BibTeX Editor',
  version: '1.0.0',
  
  onActivate(context: PluginContext) {
    // Add panel for editing .bib files
    context.ui.addPanel({
      id: 'bibtex-editor',
      title: 'References',
      position: 'right',
      component: BibTeXEditorPanel
    });
    
    // Watch for .bib file opens
    context.document.onFileOpen((file) => {
      if (file.endsWith('.bib')) {
        context.ui.showPanel('bibtex-editor');
      }
    });
  }
};
```

---

### **Plugin Development Workflow**

```bash
# 1. Create plugin from template
npx create-latex-plugin my-plugin

# 2. Develop locally
cd my-plugin
npm install
npm run dev  # Hot-reload

# 3. Test in development environment
# Plugin served from localhost:3000

# 4. Build for production
npm run build
# Outputs: dist/index.js + plugin.json

# 5. Publish to marketplace
npx latex-plugin-cli publish
# Uploads to MinIO, registers in MongoDB

# 6. Users install from marketplace UI
# Plugin downloaded and enabled
```

---

### **Plugin Security**

**Sandboxing**:
- Frontend plugins run in same context (trusted)
- Backend plugins run in Docker containers (untrusted)
- API permissions system

**Permissions Model**:
```json
// plugin.json
{
  "permissions": [
    "editor.read",      // Read editor content
    "editor.write",     // Modify editor content
    "document.read",    // Read project files
    "document.write",   // Modify project files
    "network.http",     // Make HTTP requests
    "ui.panels"         // Add UI panels
  ]
}
```

User approves permissions on plugin install.

---

### **Plugin Marketplace UI**

```typescript
// Frontend: Browse and install plugins
interface PluginMarketplace {
  // Browse plugins
  featured: Plugin[];
  categories: Category[];
  search(query: string): Plugin[];
  
  // Install/uninstall
  install(pluginId: string): Promise<void>;
  uninstall(pluginId: string): Promise<void>;
  
  // Manage installed
  list(): InstalledPlugin[];
  enable(pluginId: string): void;
  disable(pluginId: string): void;
  configure(pluginId: string, settings: any): void;
}
```

---

### **Initial Built-in "Plugins"** (Ship with core)

Rather than true plugins, these features ship as part of the core but use the plugin API internally:

1. **LaTeX Snippets** - Common LaTeX commands
2. **PDF Preview** - PDF viewer panel
3. **File Explorer** - Project file tree
4. **Git Panel** - Git sync UI
5. **Chat** - Collaboration chat
6. **Comments** - Comment threads

This validates the plugin API and provides essential features.

---

### **Future Plugin Examples**

1. **AI Assistant** - GPT-powered LaTeX help
2. **Zotero Connector** - Import citations
3. **TikZ Editor** - Visual diagram editor
4. **Template Gallery** - Pre-made LaTeX templates
5. **Overleaf Import** - Import Overleaf projects
6. **Math OCR** - Convert images to LaTeX
7. **Collaboration Analytics** - Track edits, contributions

---

## Questions Answered ✅

### 1. **LaTeX Package Installation**
**Decision: No custom package installation** ✅

- Use **TeX Live Full** in Docker compilation
- All standard packages available out of the box
- No security risk from user-uploaded packages
- Faster compilation (packages pre-installed)
- SwiftLaTeX WASM comes with common packages

**Benefits**:
- ✅ Simple, secure, predictable
- ✅ No package management complexity
- ✅ Consistent compilation environment
- ✅ Users can request missing packages (we add to base image)

---

### 2. **Offline Support**
**Decision: No offline support** ✅

- Requires complex sync logic
- Not a priority for collaborative editor
- Users can export projects and work locally with Git
- Online-first design simplifies architecture

**Alternative**: Users can:
- Export project as ZIP
- Clone via Git sync
- Work locally with their own LaTeX installation
- Re-import/push changes when online

---

### 3. **Mobile Support**
**Decision: Yes - Full mobile editing support** ✅

- **CodeMirror 6** selected specifically for mobile support
- Touch-friendly UI
- Responsive design
- Mobile-optimized editor
- Bottom action bars (thumb-friendly)
- Virtual keyboard support
- Compilation via Docker (server-side)

**Mobile Features**:
- ✅ Full editing capabilities
- ✅ Real-time collaboration
- ✅ PDF preview
- ✅ Comments and chat
- ✅ Change tracking (view/accept/reject)
- ⚠️ Simplified UI (focused on essential features)

---

### 4. **Billing/Quotas**
**Decision: No billing system** ✅

- Simple deployment
- No payment processing
- No quota management
- Suitable for institutional/self-hosted deployment

**Optional Future**:
- Storage limits can be added later if needed
- Compilation rate limiting via Redis
- User quotas in MongoDB (optional)

---

### 5. **LaTeX Templates/Examples**
**Decision: Yes - Template gallery** ✅

**Implementation**:
- Built-in template collection
- Common document types:
  - Academic paper (ACM, IEEE, Springer formats)
  - Thesis/Dissertation
  - Resume/CV
  - Letter
  - Presentation (Beamer)
  - Book
  - Article
- Template browser in UI
- "New from Template" option
- Templates stored in MinIO
- Community templates (future: user submissions)

**Template Structure**:
```
templates/
├── academic-paper/
│   ├── acm/
│   │   ├── main.tex
│   │   ├── references.bib
│   │   └── preview.png
│   ├── ieee/
│   └── springer/
├── thesis/
├── cv/
└── presentation/
```

---

### 6. **Reference Manager Integration**
**Decision: Yes - via web-based integrations and plugins** ✅

**Priority Integrations**:

**Tier 1 (High Priority)**:
1. **DOI Fetcher** ✅
   - Enter DOI → Auto-fetch BibTeX entry
   - API: CrossRef, DataCite
   - Plugin: Frontend + lightweight backend

2. **ORCID** ✅
   - Author identification
   - Fetch author publications
   - Auto-populate co-author info
   - OAuth integration

3. **Zotero** ✅
   - Zotero Web API
   - Import collections
   - Sync library
   - Better Together integration (web API)

**Tier 2 (Medium Priority)**:
4. **Mendeley** (maybe)
   - Mendeley API
   - Similar to Zotero integration

**Implementation via Plugins**:
```typescript
// DOI Fetcher Plugin
{
  id: "doi-fetcher",
  name: "DOI to BibTeX",
  type: "hybrid",
  frontend: {
    command: "insertCitation",
    ui: "modal"  // DOI input dialog
  },
  backend: {
    type: "node",
    endpoints: ["/api/doi/fetch"]
  }
}

// Zotero Plugin
{
  id: "zotero-connector",
  name: "Zotero Integration",
  type: "hybrid",
  frontend: {
    panel: "references",  // Sidebar with Zotero library
    oauth: "zotero"
  },
  backend: {
    type: "node",
    endpoints: [
      "/api/zotero/auth",
      "/api/zotero/collections",
      "/api/zotero/items"
    ]
  }
}
```

**BibTeX Management**:
- Built-in BibTeX editor (syntax highlighting)
- BibTeX validation
- Duplicate detection
- Citation key management
- Integration with `\cite{}` autocomplete

---

### 7. **Access Control Granularity**
**Decision: 4-tier role-based access control** ✅

**Roles**:

1. **Owner** (Project Creator)
   - Full control
   - Can delete project
   - Manage collaborators
   - Change project settings
   - Transfer ownership

2. **Editor** (Full Edit Rights)
   - Edit all documents
   - Create/delete files
   - Compile project
   - Accept/reject changes
   - Add/edit comments
   - Chat access
   - Cannot: Delete project, change collaborators

3. **Reviewer** (Review + Comment)
   - View all documents
   - Add comments
   - Track changes (suggest edits)
   - View PDF
   - Chat access
   - Cannot: Direct edit, accept/reject changes, create/delete files

4. **Reader** (View Only)
   - View all documents
   - View PDF
   - Download project
   - Cannot: Edit, comment, chat

**Permission Matrix**:
```
Action              | Owner | Editor | Reviewer | Reader
--------------------|-------|--------|----------|-------
View documents      |   ✅  |   ✅   |    ✅    |   ✅
Edit documents      |   ✅  |   ✅   |    ❌    |   ❌
Track changes mode  |   ✅  |   ✅   |    ✅    |   ❌
Accept/reject       |   ✅  |   ✅   |    ❌    |   ❌
Add comments        |   ✅  |   ✅   |    ✅    |   ❌
Create/delete files |   ✅  |   ✅   |    ❌    |   ❌
Compile             |   ✅  |   ✅   |    ❌    |   ❌
View PDF            |   ✅  |   ✅   |    ✅    |   ✅
Chat                |   ✅  |   ✅   |    ✅    |   ❌
Download            |   ✅  |   ✅   |    ✅    |   ✅
Git sync            |   ✅  |   ✅   |    ❌    |   ❌
Manage collab.      |   ✅  |   ❌   |    ❌    |   ❌
Delete project      |   ✅  |   ❌   |    ❌    |   ❌
```

**Implementation**:
```javascript
// MongoDB: projects collection
{
  _id: ObjectId,
  name: "My Paper",
  owner: ObjectId,  // User ID
  
  collaborators: [
    {
      userId: ObjectId,
      role: "editor",
      addedAt: Date,
      addedBy: ObjectId
    },
    {
      userId: ObjectId,
      role: "reviewer",
      addedAt: Date,
      addedBy: ObjectId
    }
  ],
  
  // Optional: Anonymous sharing
  publicLink: {
    enabled: boolean,
    token: string,
    role: "reader",  // Only reader role for public links
    expiresAt: Date
  }
}
```

**Additional Features**:
- **Anonymous viewing links**: Generate shareable read-only links
- **Expiring access**: Set expiration dates for collaborators
- **Invitation system**: Email invitations with role assignment
- **Activity log**: Track who did what (audit trail)

---

## Decisions Summary

> **Quick Reference**: All architectural and operational decisions made for GoGoLaTeX

### 🎯 **Core Architecture Decisions**

| # | Area | Decision | Rationale |
|---|------|----------|-----------|
| 1 | **Real-time Collaboration** | Yjs (CRDT) | Modern, offline-capable, simpler than OT |
| 2 | **Backend** | Hybrid Go + Node.js | Go for REST/Docker, Node.js for WebSocket/Git |
| 3 | **Storage Architecture** | Two-tier: Redis → MinIO | Redis hot state, MinIO source of truth, MongoDB metadata only |
| 4 | **Git Integration** | Git Sync (external repos) | Simple push/pull, users manage Git externally |
| 5 | **Change Tracking** | JSON files in project | Portable, survives migration, Git-compatible |
| 6 | **LaTeX Compilation** | WASM + Docker (user choice) | WASM client-side (fast/free), Docker fallback (reliable) |
| 7 | **Scaling Strategy** | Horizontal from day one | Target 1000+ concurrent users |
| 8 | **Authentication** | OIDC (Keycloak) | Industry standard, MongoDB for user settings |

### 🎨 **Frontend & User Experience**

| # | Area | Decision | Rationale |
|---|------|----------|-----------|
| 9 | **Editor** | CodeMirror 6 | Mobile support (200KB vs 2.5MB), touch-friendly, excellent Yjs integration |
| 10 | **Mobile Support** | Yes - Full editing | Primary reason for CodeMirror 6 selection |
| 11 | **Offline Support** | No | Online-first, users can export for offline work |
| 12 | **LaTeX Packages** | TeX Live Full (pre-installed) | No custom installation, all standard packages available |
| 13 | **Templates** | Yes - Built-in gallery | Academic papers, thesis, resume, Beamer, etc. |
| 14 | **Access Control** | 4-tier roles | Owner, Editor, Reviewer, Reader + anonymous links |

### 🔌 **Extensibility & Integrations**

| # | Area | Decision | Rationale |
|---|------|----------|-----------|
| 15 | **Plugin Architecture** | Frontend + Backend hybrid | Plugins can have both components, Docker for backend |
| 16 | **Reference Managers** | Yes (via plugins) | Priority: DOI, ORCID, Zotero, Mendeley |
| 17 | **Billing/Quotas** | No | Simple deployment, optional future enhancement |

### ⚙️ **Operational & DevOps**

| # | Area | Decision | Rationale |
|---|------|----------|-----------|
| 18 | **Container Naming** | `gogolatex-*` prefix | Consistent branding (changed from `texlyre-*`) |
| 19 | **Network** | `gogolatex-network` | Matches project name |
| 20 | **CI/CD** | None (manual) | Solo developer, simple deployment |
| 21 | **Monitoring** | Prometheus + Grafana | Industry standard metrics and dashboards |
| 22 | **Backups** | Cron jobs → MinIO | MongoDB: 30 daily + 12 monthly, Redis: 7 daily |
| 23 | **SSL/TLS** | nginx reverse proxy | Admin manages Let's Encrypt certificates |
| 24 | **Rate Limiting** | Per-user (not IP) | NAT-friendly: 1000 req/hour, 50 compilations/hour |
| 25 | **Email Service** | SMTP (configurable) | Provider-agnostic: Gmail, SendGrid, Mailgun, AWS SES |
| 26 | **Error Logging** | Structured + ELK/Loki | Zap/Winston, optional Sentry for production |
| 27 | **Testing** | Unit (70%) + E2E | Playwright for E2E, vitest/jest for unit tests |
| 28 | **API Documentation** | OpenAPI/Swagger + MkDocs | Auto-generated from code, user docs in Markdown |
| 29 | **Development Workflow** | Simple Git (solo dev) | main + feature branches, self-review |

---

### 📊 **Detailed Decision Breakdown**

#### **1. Editor: CodeMirror 6 Over Monaco**

**Why CodeMirror 6**:
- ✅ **Mobile support** - Touch-friendly, mobile-optimized (primary driver)
- ✅ **Lightweight** - 200KB vs Monaco's 2.5MB (10× smaller bundle)
- ✅ **Performance** - Better on mobile devices and slower connections
- ✅ **Yjs integration** - Excellent `y-codemirror.next` bindings for real-time
- ✅ **Customizable** - Can achieve VS Code-like aesthetic with themes

**Trade-offs Accepted**:
- Need to build some features from scratch (IntelliSense, diff editor)
- Smaller ecosystem than Monaco
- Custom LaTeX syntax highlighting implementation

---

#### **2. Compilation: Hybrid WASM + Docker with User Choice**

**User Settings**:
```typescript
compilationSettings: {
  engine: "auto" | "wasm" | "docker",  // User selects
  autoFallback: true,                   // Fallback to Docker if WASM fails
  showEngineChoice: true                // Show engine in UI
}
```

**Engines**:
- **SwiftLaTeX WASM**: Client-side, instant feedback, free, scales infinitely
- **Docker (TeX Live Full)**: Server-side, all packages, 100% reliable

**Benefits**:
- ✅ Power users can force Docker for maximum reliability
- ✅ Desktop users enjoy instant WASM compilation
- ✅ Mobile defaults to Docker (more reliable on mobile)
- ✅ Testing: Users can compare WASM vs Docker results
- ✅ Cost savings: ~$1,200-2,400/month with 1000 users (80% use free WASM)

---

#### **3. Storage: Simplified Two-Tier Architecture**

**Data Flow**:
```
Yjs (in-memory) → Redis (hot state, 7-day TTL) → MinIO (cold storage, source of truth)
                                                      ↓
                                                  MongoDB (metadata only)
```

**Why This Approach**:
- ✅ **No content duplication**: LaTeX files only in MinIO
- ✅ **Redis for speed**: Fast Yjs state recovery, pub/sub for scaling
- ✅ **MinIO as truth**: Single source, Git-compatible, human-readable .tex files
- ✅ **MongoDB simplified**: Only metadata (users, projects, permissions)
- ✅ **Portable**: Projects can be moved between servers easily

---

#### **4. Access Control: 4-Tier Role System**

**Permission Matrix**:
```
Action              | Owner | Editor | Reviewer | Reader
--------------------|-------|--------|----------|-------
View documents      |   ✅  |   ✅   |    ✅    |   ✅
Edit documents      |   ✅  |   ✅   |    ❌    |   ❌
Track changes mode  |   ✅  |   ✅   |    ✅    |   ❌
Accept/reject       |   ✅  |   ✅   |    ❌    |   ❌
Add comments        |   ✅  |   ✅   |    ✅    |   ❌
Compile             |   ✅  |   ✅   |    ❌    |   ❌
Git sync            |   ✅  |   ✅   |    ❌    |   ❌
Manage collab.      |   ✅  |   ❌   |    ❌    |   ❌
Delete project      |   ✅  |   ❌   |    ❌    |   ❌
```

**Additional Features**:
- Anonymous sharing links (read-only)
- Expiring access with date limits
- Activity log for audit trail

---

#### **5. Plugin Architecture: Frontend + Backend Hybrid**

**Key Principle**: Plugins can have frontend and/or backend components

**Plugin Types**:
1. **Frontend only** - UI extensions, editor features, syntax highlighting
2. **Backend only** - Processing services, APIs, data transformations
3. **Hybrid** - Both components (e.g., reference manager with UI + API)

**Plugin Manifest Example**:
```json
{
  "id": "zotero-integration",
  "name": "Zotero Reference Manager",
  "version": "1.0.0",
  "type": "hybrid",
  "frontend": {
    "main": "dist/frontend.js",
    "style": "dist/style.css"
  },
  "backend": {
    "type": "docker",
    "image": "gogolatex-plugins/zotero:1.0.0",
    "env": ["ZOTERO_API_KEY"]
  }
}
```

---

#### **6. Scaling: Horizontal from Day One**

**Target**: 1000+ concurrent users

**Scaling Numbers** (estimated):
```
Go REST Services:        5-10 instances (stateless)
Node.js Realtime:        5-10 instances (200 WebSocket connections each)
Redis Cluster:           3 nodes (master + 2 replicas)
MongoDB Replica Set:     3 nodes (primary + 2 secondaries)
MinIO:                   4+ nodes (distributed, erasure coding)
Compilation Workers:     20-30 instances (Docker only, reduced by WASM)
```

**Key Patterns**:
- **Stateless services**: Any request to any server (JWT auth)
- **Redis pub/sub**: Cross-server WebSocket communication
- **Worker pools**: Queue-based compilation (Bull/BullMQ)
- **Auto-scaling**: Based on CPU/memory/queue length

---

#### **7. LaTeX Packages: TeX Live Full (No Custom Installation)**

**Decision**: All packages pre-installed, no user uploads

**Rationale**:
- ✅ All standard packages available (~4GB TeX Live Full)
- ✅ No security risk from user-uploaded .sty files
- ✅ Faster compilation (pre-installed, no download)
- ✅ Consistent environment across all users
- ✅ Simpler architecture (no package management system)

**If Users Need Missing Packages**:
1. User submits package request
2. Admin reviews and adds to base Docker image
3. Everyone benefits from the addition

---

#### **8. Mobile Support: Full Editing Capabilities**

**Implementation**:
- CodeMirror 6 with touch-optimized interface
- Responsive design (desktop, tablet, mobile)
- Bottom action bars (thumb-friendly on mobile)
- Simplified mobile toolbar (essential features only)
- Virtual keyboard support with LaTeX symbols
- Docker compilation (server-side, reliable on mobile)

**Mobile Features**:
- ✅ Full document editing
- ✅ Real-time collaboration
- ✅ PDF preview (responsive)
- ✅ Comments and chat
- ✅ Change tracking
- ⚠️ Simplified UI (prioritized features for small screens)

---

#### **9. Reference Managers: Plugin-Based Integration**

**Priority Order**:

**Tier 1** (High Priority - Build first):
1. **DOI Fetcher** - CrossRef/DataCite API, auto-populate BibTeX
2. **ORCID** - Author identification, pull publication lists
3. **Zotero** - Web API integration, collections, sync

**Tier 2** (Medium Priority - Maybe later):
4. **Mendeley** - API integration (if API available and stable)

**Implementation**: Hybrid plugins (frontend UI + backend API calls)

---

#### **10. Templates: Built-in Gallery**

**Included Templates**:
- Academic paper (ACM, IEEE, Springer, Nature)
- Thesis/Dissertation (university styles)
- Resume/CV (professional formats)
- Letter (formal, cover letter)
- Presentation (Beamer themes)
- Book (chapters, bibliography)
- Article (journal formats)

**Storage**: MinIO `templates/` directory  
**Features**: Preview, one-click project creation, user ratings

---

#### **11. Monitoring: Prometheus + Grafana**

**Prometheus Metrics**:
- Service metrics: request count, latency, error rates
- System metrics: CPU, memory, disk, network
- Custom metrics: document opens, compilations, active users, WebSocket connections

**Grafana Dashboards**:
- Pre-built: Go services, Node.js, MongoDB, Redis, Docker
- Custom: Application-specific (real-time users, compilation queue)

**Alerting** (Prometheus Alertmanager):
- High error rates (>5%)
- Service down (health check failed)
- High resource usage (CPU >80%, memory >90%)
- Long compilation queue (>100 jobs)

---

#### **12. Backup Strategy: Cron-Based**

**MongoDB Backups**:
```bash
# Daily backup at 2 AM
0 2 * * * mongodump --uri="mongodb://..." | gzip > backup.gz && \
          mc cp backup.gz minio/backups/mongodb-$(date +\%Y\%m\%d).gz
```
- **Retention**: 30 daily backups + 12 monthly backups
- **Tool**: `mongodump` + gzip compression

**Redis Backups**:
```bash
# Daily RDB snapshot
0 3 * * * redis-cli BGSAVE && \
          mc cp /var/lib/redis/dump.rdb minio/backups/redis-$(date +\%Y\%m\%d).rdb
```
- **Retention**: 7 daily snapshots (cache data, short retention)

**MinIO Replication**:
- Cross-region replication to secondary MinIO cluster or S3-compatible storage
- Disaster recovery: Restore scripts in repository

---

#### **13. Rate Limiting: Per-User (NAT-Friendly)**

**Why Not IP**: NAT firewalls cause false positives (entire office blocked)

**Limits** (per authenticated user):
- API requests: **1000 req/hour**
- LaTeX compilation: **50 jobs/hour**
- WebSocket connections: **10 concurrent**
- File uploads: **100 MB/hour**

**Implementation**: Redis-based
- Go: `go-redis/redis_rate`
- Node.js: `rate-limiter-flexible`

**Anonymous Users** (public links): Stricter IP-based limits as fallback

---

#### **14. Testing Strategy**

**Unit Tests** (70% coverage goal):
- **Go**: `testing` package + `testify/assert`
  - Critical: Auth, compilation orchestration, storage
- **Node.js**: `jest` or `vitest`
  - Critical: Yjs collaboration, Git operations
- **Frontend**: `vitest` + `@testing-library/react`
  - Critical: Editor, real-time sync, UI components

**E2E Tests** (Playwright):
```typescript
// Example test
test('real-time collaboration', async ({ page, context }) => {
  const page1 = await context.newPage();
  const page2 = await context.newPage();
  
  // User 1 logs in and creates document
  await page1.goto('/login');
  await page1.fill('[name=email]', 'user1@example.com');
  // ...
  
  // User 2 joins same document
  await page2.goto('/document/123');
  
  // User 1 types
  await page1.type('.cm-editor', 'Hello');
  
  // User 2 sees update
  await expect(page2.locator('.cm-editor')).toContainText('Hello');
});
```

**Test Scenarios**:
- User login flow
- Document creation and editing
- Real-time collaboration (multiple users)
- LaTeX compilation (WASM + Docker)
- PDF preview
- Git sync operations
- Change tracking (accept/reject)

---

#### **15. API Documentation**

**REST APIs**: OpenAPI/Swagger
- Auto-generated from code comments (Go: `swaggo/swag`)
- Swagger UI at `/api/docs`
- OpenAPI spec at `/api/openapi.json`

**WebSocket API**: Custom documentation
- Event types, payloads, examples
- Hosted alongside Swagger UI

**User Documentation**: MkDocs or Docusaurus
- Markdown-based, version controlled
- Sections:
  - Getting Started (installation, first document)
  - Features (collaboration, compilation, Git sync)
  - API Reference (for plugin developers)
  - Deployment (Docker Compose, scaling, backups)
- Hosted statically via nginx or GitHub Pages

---

## Conclusion

The proposed tech stack is solid and well-suited for the requirements:

✅ **Go**: Perfect for REST APIs, Docker orchestration, auth  
✅ **Node.js**: Excellent for real-time collaboration and Git operations  
✅ **MongoDB**: Metadata only (users, projects, permissions) - no content duplication  
✅ **Redis**: Essential for real-time features, Yjs persistence, caching, pub/sub, horizontal scaling  
✅ **MinIO**: Single source of truth for .tex files, versioning, Git compatibility  
✅ **React + CodeMirror 6**: Lightweight, mobile-friendly editor  
✅ **Yjs**: Modern, robust real-time collaboration with CRDT  
✅ **SwiftLaTeX WASM**: Client-side compilation (user selectable, instant, free, scales infinitely)  
✅ **Docker (TeX Live Full)**: Server compilation fallback, all packages included  
✅ **Keycloak**: OpenID Connect authentication  

**Key Architecture Principles**:
1. ✅ Horizontal scaling from day one (1000+ users)
2. ✅ Simplified two-tier storage (Redis hot state → MinIO cold storage)
3. ✅ Single source of truth (MinIO for all .tex files)
4. ✅ Client-side compilation (WASM) for 80% of users (cost savings)
5. ✅ Plugin architecture for extensibility (frontend and/or backend)
6. ✅ External Git for complexity management
7. ✅ JSON files for user-facing data (portability)
8. ✅ Redis pub/sub for multi-server coordination
9. ✅ Stateless services for easy scaling
10. ✅ No content in MongoDB (simpler, cleaner, more portable)
11. ✅ **Mobile-first editor** (CodeMirror 6, touch-friendly)
12. ✅ **TeX Live Full** (all packages, no custom installation)
13. ✅ **4-tier access control** (Owner/Editor/Reviewer/Reader)
14. ✅ **Template gallery** (common document types)
15. ✅ **Reference manager plugins** (DOI, ORCID, Zotero, Mendeley)
16. ✅ **Container naming**: `gogolatex-*` prefix
17. ✅ **Network**: `gogolatex-network`
18. ✅ **Monitoring**: Prometheus + Grafana (industry standard)
19. ✅ **Backups**: Cron jobs for MongoDB/Redis → MinIO
20. ✅ **SSL/TLS**: nginx reverse proxy (admin manages Let's Encrypt)
21. ✅ **Rate limiting**: Per-user (not IP, NAT-friendly)
22. ✅ **Email**: SMTP with configurable credentials
23. ✅ **Error logging**: Structured logs + ELK/Loki, optional Sentry
24. ✅ **Testing**: Unit tests (70% coverage) + Playwright E2E
25. ✅ **API docs**: OpenAPI/Swagger + MkDocs for user docs
26. ✅ **Development**: Solo developer, simple Git workflow

**Next Steps**:
1. Set up development environment (Docker Compose with gogolatex naming)
2. Implement core authentication (Go + Keycloak)
3. Build basic CodeMirror 6 editor integration with mobile support
4. Implement Yjs real-time collaboration
5. Set up Redis pub/sub for scaling
6. Implement LaTeX compilation service (WASM + Docker with TeX Live Full)
7. Add plugin system foundation (frontend/backend architecture)
8. Implement 4-tier access control
9. Create template gallery
10. Build reference manager plugins (DOI, ORCID, Zotero)

This architecture provides a solid foundation that can scale from MVP to production with 1000+ users.
