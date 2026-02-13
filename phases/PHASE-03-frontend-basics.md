# Phase 3: Frontend Basics

**Duration**: 3-4 days  
**Goal**: React + TypeScript frontend with CodeMirror 6 editor and authentication

**Prerequisites**: Phase 2 completed, auth service running

---

## Prerequisites

- [ ] Phase 2 Go auth service completed and running
- [ ] Auth service accessible at http://localhost:5001
- [ ] Keycloak running and configured
- [ ] Node.js 20+ and npm installed
- [ ] Basic familiarity with React, TypeScript, and Vite

---

## Task 1: Vite + React + TypeScript Setup (1 hour)

### 1.1 Create Vite Project

```bash
cd latex-collaborative-editor/frontend

# Create Vite project with React + TypeScript template
npm create vite@latest . -- --template react-ts

# Install dependencies
npm install
```

### 1.2 Install Core Dependencies

```bash
# React Router for navigation
npm install react-router-dom

# HTTP client
npm install axios

# State management
npm install zustand

# UI/Styling
npm install tailwindcss postcss autoprefixer
npm install -D @tailwindcss/forms @tailwindcss/typography

# Icons
npm install lucide-react

# Utilities
npm install clsx tailwind-merge

# Date handling
npm install date-fns
```

### 1.3 Install CodeMirror 6

```bash
# Core CodeMirror packages
npm install @codemirror/state @codemirror/view @codemirror/commands

# Extensions
npm install @codemirror/language @codemirror/language-data
npm install @codemirror/autocomplete @codemirror/lint
npm install @codemirror/search

# LaTeX support
npm install @codemirror/legacy-modes

# Theme
npm install @codemirror/theme-one-dark

# Line numbers and other basics
npm install @codemirror/gutter
```

### 1.4 Initialize Tailwind CSS

```bash
npx tailwindcss init -p
```

Create: `tailwind.config.js`

```javascript
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // VS Code inspired colors
        vscode: {
          bg: '#1e1e1e',
          sidebar: '#252526',
          panel: '#2d2d30',
          border: '#454545',
          text: '#cccccc',
          textMuted: '#858585',
          primary: '#007acc',
          success: '#4ec9b0',
          warning: '#ce9178',
          error: '#f48771',
        }
      },
      fontFamily: {
        mono: ['Consolas', 'Monaco', 'Courier New', 'monospace'],
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/typography'),
  ],
  darkMode: 'class',
}
```

### 1.5 Configure Vite

Update: `vite.config.ts`

```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 3000,
    host: '0.0.0.0',
    proxy: {
      '/api': {
        target: 'http://localhost:5001',
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
    rollupOptions: {
      output: {
        manualChunks: {
          'codemirror': [
            '@codemirror/state',
            '@codemirror/view',
            '@codemirror/language',
          ],
        },
      },
    },
  },
})
```

### 1.6 TypeScript Configuration

Update: `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,

    /* Bundler mode */
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",

    /* Linting */
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,

    /* Path aliases */
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

### 1.7 Create Folder Structure

```bash
mkdir -p src/{components,pages,services,hooks,utils,stores,types,styles}
mkdir -p src/components/{common,layout,editor}
mkdir -p src/pages/{auth,dashboard,editor}
```

### 1.8 Setup Global Styles

Create: `src/styles/index.css`

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

/* VS Code inspired theme */
@layer base {
  :root {
    --color-bg: #ffffff;
    --color-fg: #1e1e1e;
    --color-border: #e5e7eb;
    --color-primary: #007acc;
  }

  .dark {
    --color-bg: #1e1e1e;
    --color-fg: #cccccc;
    --color-border: #454545;
    --color-primary: #007acc;
  }
}

@layer components {
  .btn {
    @apply px-4 py-2 rounded font-medium transition-colors;
  }

  .btn-primary {
    @apply bg-blue-600 text-white hover:bg-blue-700;
  }

  .btn-secondary {
    @apply bg-gray-200 text-gray-800 hover:bg-gray-300 dark:bg-gray-700 dark:text-gray-200;
  }

  .input {
    @apply w-full px-3 py-2 border rounded focus:outline-none focus:ring-2 focus:ring-blue-500;
  }

  .card {
    @apply bg-white dark:bg-vscode-sidebar rounded-lg shadow p-6;
  }
}

/* CodeMirror custom styles */
.cm-editor {
  @apply h-full border-0 outline-none;
}

.cm-scroller {
  @apply font-mono text-sm;
}

/* Mobile optimizations */
@media (max-width: 768px) {
  .cm-editor {
    font-size: 14px;
  }
}
```

Update: `src/main.tsx`

```typescript
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.tsx'
import './styles/index.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
```

**Verification**:
```bash
npm run dev
# Should start at http://localhost:3000
```

---

## Task 2: Type Definitions (30 min)

### 2.1 API Types

Create: `src/types/api.ts`

```typescript
// User types
export interface User {
  id: string
  email: string
  name: string
  settings: UserSettings
  createdAt: string
}

export interface UserSettings {
  theme: 'light' | 'dark'
  editorFontSize: number
  autoCompile: boolean
  vimMode: boolean
  autoSave: boolean
  autoSaveInterval: number
  spellCheck: boolean
  spellCheckLanguage: string
  compilationEngine: 'auto' | 'wasm' | 'docker'
}

// Auth types
export interface LoginResponse {
  accessToken: string
  refreshToken: string
  expiresIn: number
  user: User
}

export interface RefreshResponse {
  accessToken: string
  refreshToken: string
  expiresIn: number
}

// Project types
export interface Project {
  id: string
  name: string
  description?: string
  owner: string
  collaborators: Collaborator[]
  createdAt: string
  updatedAt: string
}

export interface Collaborator {
  userId: string
  role: 'owner' | 'editor' | 'reviewer' | 'reader'
  addedAt: string
}

// Document types
export interface Document {
  id: string
  projectId: string
  path: string
  content?: string
  lastModifiedAt: string
  lastModifiedBy: string
}

// API Error
export interface APIError {
  error: string
  message?: string
  statusCode?: number
}
```

### 2.2 Component Props Types

Create: `src/types/components.ts`

```typescript
import { ReactNode } from 'react'

export interface LayoutProps {
  children: ReactNode
}

export interface EditorProps {
  initialContent?: string
  onChange?: (content: string) => void
  readOnly?: boolean
  language?: string
}

export interface ProtectedRouteProps {
  children: ReactNode
}
```

**Verification**:
```bash
npm run build
# Should compile without errors
```

---

## Task 3: Authentication Service & Store (2 hours)

### 3.1 Axios Client Configuration

Create: `src/services/api.ts`

```typescript
import axios, { AxiosError, AxiosInstance, AxiosResponse, InternalAxiosRequestConfig } from 'axios'
import { useAuthStore } from '@/stores/authStore'

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:5001'

// Create axios instance
const apiClient: AxiosInstance = axios.create({
  baseURL: API_BASE_URL,
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json',
  },
})

// Request interceptor - add auth token
apiClient.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    const token = useAuthStore.getState().accessToken
    if (token) {
      config.headers.Authorization = `Bearer ${token}`
    }
    return config
  },
  (error: AxiosError) => {
    return Promise.reject(error)
  }
)

// Response interceptor - handle token refresh
apiClient.interceptors.response.use(
  (response: AxiosResponse) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config as InternalAxiosRequestConfig & { _retry?: boolean }

    // If 401 and not already retried, try to refresh token
    if (error.response?.status === 401 && !originalRequest._retry) {
      originalRequest._retry = true

      try {
        const refreshToken = useAuthStore.getState().refreshToken
        if (!refreshToken) {
          throw new Error('No refresh token available')
        }

        // Call refresh endpoint
        const response = await axios.post(`${API_BASE_URL}/auth/refresh`, {
          refreshToken,
        })

        const { accessToken, refreshToken: newRefreshToken } = response.data

        // Update tokens in store
        useAuthStore.getState().setTokens(accessToken, newRefreshToken)

        // Retry original request with new token
        originalRequest.headers.Authorization = `Bearer ${accessToken}`
        return apiClient(originalRequest)
      } catch (refreshError) {
        // Refresh failed, logout user
        useAuthStore.getState().clearAuth()
        window.location.href = '/login'
        return Promise.reject(refreshError)
      }
    }

    return Promise.reject(error)
  }
)

export default apiClient
```

### 3.2 Auth Service

Create: `src/services/authService.ts`

```typescript
import apiClient from './api'
import { LoginResponse, RefreshResponse, User } from '@/types/api'

const KEYCLOAK_URL = import.meta.env.VITE_KEYCLOAK_URL || 'http://localhost:8080'
const KEYCLOAK_REALM = import.meta.env.VITE_KEYCLOAK_REALM || 'gogotex'
const KEYCLOAK_CLIENT_ID = import.meta.env.VITE_KEYCLOAK_CLIENT_ID || 'gogotex-backend'
const REDIRECT_URI = import.meta.env.VITE_REDIRECT_URI || 'http://localhost:3000/auth/callback'

class AuthService {
  /**
   * Redirect to Keycloak login page
   */
  redirectToLogin(): void {
    const authUrl = `${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/auth`
    const params = new URLSearchParams({
      client_id: KEYCLOAK_CLIENT_ID,
      redirect_uri: REDIRECT_URI,
      response_type: 'code',
      scope: 'openid profile email',
      // Add state for CSRF protection
      state: this.generateState(),
    })

    // Store state in sessionStorage for verification
    sessionStorage.setItem('oauth_state', params.get('state')!)

    window.location.href = `${authUrl}?${params.toString()}`
  }

  /**
   * Handle OAuth callback with authorization code
   */
  async handleCallback(code: string, state: string): Promise<LoginResponse> {
    // Verify state for CSRF protection
    const storedState = sessionStorage.getItem('oauth_state')
    if (state !== storedState) {
      throw new Error('Invalid state parameter')
    }
    sessionStorage.removeItem('oauth_state')

    // Exchange code for tokens
    const response = await apiClient.post<LoginResponse>('/auth/login', {
      authCode: code,
    })

    return response.data
  }

  /**
   * Refresh access token
   */
  async refreshToken(refreshToken: string): Promise<RefreshResponse> {
    const response = await apiClient.post<RefreshResponse>('/auth/refresh', {
      refreshToken,
    })

    return response.data
  }

  /**
   * Get current user info
   */
  async getMe(): Promise<User> {
    const response = await apiClient.get<User>('/auth/me')
    return response.data
  }

  /**
   * Logout user
   */
  async logout(): Promise<void> {
    try {
      await apiClient.post('/auth/logout')
    } catch (error) {
      console.error('Logout error:', error)
    }

    // Redirect to Keycloak logout
    const logoutUrl = `${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/logout`
    const params = new URLSearchParams({
      redirect_uri: window.location.origin,
    })

    window.location.href = `${logoutUrl}?${params.toString()}`
  }

  /**
   * Generate random state for CSRF protection
   */
  private generateState(): string {
    return Math.random().toString(36).substring(2, 15)
  }
}

export const authService = new AuthService()
```

### 3.3 Zustand Auth Store

Create: `src/stores/authStore.ts`

```typescript
import { create } from 'zustand'
import { persist, createJSONStorage } from 'zustand/middleware'
import { User } from '@/types/api'

interface AuthState {
  // State
  isAuthenticated: boolean
  user: User | null
  accessToken: string | null
  refreshToken: string | null
  isLoading: boolean

  // Actions
  setAuth: (data: { user: User; accessToken: string; refreshToken: string }) => void
  setTokens: (accessToken: string, refreshToken: string) => void
  setUser: (user: User) => void
  setLoading: (isLoading: boolean) => void
  clearAuth: () => void
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      // Initial state
      isAuthenticated: false,
      user: null,
      accessToken: null,
      refreshToken: null,
      isLoading: false,

      // Set auth data (after login)
      setAuth: ({ user, accessToken, refreshToken }) =>
        set({
          isAuthenticated: true,
          user,
          accessToken,
          refreshToken,
          isLoading: false,
        }),

      // Update tokens (after refresh)
      setTokens: (accessToken, refreshToken) =>
        set({
          accessToken,
          refreshToken,
        }),

      // Update user info
      setUser: (user) =>
        set({
          user,
        }),

      // Set loading state
      setLoading: (isLoading) =>
        set({
          isLoading,
        }),

      // Clear auth (logout)
      clearAuth: () =>
        set({
          isAuthenticated: false,
          user: null,
          accessToken: null,
          refreshToken: null,
          isLoading: false,
        }),
    }),
    {
      name: 'auth-storage',
      storage: createJSONStorage(() => localStorage),
      // Only persist specific fields
      partialize: (state) => ({
        isAuthenticated: state.isAuthenticated,
        user: state.user,
        accessToken: state.accessToken,
        refreshToken: state.refreshToken,
      }),
    }
  )
)
```

### 3.4 Environment Variables

Create: `.env`

```env
# API Configuration
VITE_API_URL=http://localhost:5001
VITE_WS_URL=http://localhost:4000

# Keycloak Configuration
VITE_KEYCLOAK_URL=http://localhost:8080
VITE_KEYCLOAK_REALM=gogotex
VITE_KEYCLOAK_CLIENT_ID=gogotex-backend
VITE_REDIRECT_URI=http://localhost:3000/auth/callback

# Feature Flags
VITE_ENABLE_WASM_COMPILATION=true
VITE_ENABLE_PLUGINS=false
```

Create: `.env.example`

```env
# Copy this file to .env and fill in the values

# API Configuration
VITE_API_URL=http://localhost:5001
VITE_WS_URL=http://localhost:4000

# Keycloak Configuration
VITE_KEYCLOAK_URL=http://localhost:8080
VITE_KEYCLOAK_REALM=gogotex
VITE_KEYCLOAK_CLIENT_ID=gogotex-backend
VITE_REDIRECT_URI=http://localhost:3000/auth/callback
```

**Verification**:
```bash
npm run build
# Should compile without errors
```

---

## Task 4: CodeMirror 6 Editor Component (3 hours)

### 4.1 Editor Hook

Create: `src/hooks/useCodeMirror.ts`

```typescript
import { useEffect, useRef, useState } from 'react'
import { EditorState, Extension } from '@codemirror/state'
import { EditorView, keymap, lineNumbers, highlightActiveLine } from '@codemirror/view'
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands'
import { indentOnInput, syntaxHighlighting, defaultHighlightStyle, bracketMatching } from '@codemirror/language'
import { searchKeymap, highlightSelectionMatches } from '@codemirror/search'
import { autocompletion, completionKeymap, closeBrackets, closeBracketsKeymap } from '@codemirror/autocomplete'
import { lintKeymap } from '@codemirror/lint'
import { oneDark } from '@codemirror/theme-one-dark'
import { StreamLanguage } from '@codemirror/language'
import { stex } from '@codemirror/legacy-modes/mode/stex'

interface UseCodeMirrorProps {
  initialContent?: string
  onChange?: (value: string) => void
  readOnly?: boolean
  theme?: 'light' | 'dark'
}

export const useCodeMirror = ({
  initialContent = '',
  onChange,
  readOnly = false,
  theme = 'dark',
}: UseCodeMirrorProps) => {
  const editorRef = useRef<HTMLDivElement>(null)
  const viewRef = useRef<EditorView | null>(null)
  const [editorView, setEditorView] = useState<EditorView | null>(null)

  useEffect(() => {
    if (!editorRef.current) return

    // LaTeX language support
    const latexLanguage = StreamLanguage.define(stex)

    // Build extensions array
    const extensions: Extension[] = [
      lineNumbers(),
      highlightActiveLine(),
      history(),
      indentOnInput(),
      bracketMatching(),
      closeBrackets(),
      autocompletion(),
      highlightSelectionMatches(),
      syntaxHighlighting(defaultHighlightStyle),
      keymap.of([
        ...closeBracketsKeymap,
        ...defaultKeymap,
        ...searchKeymap,
        ...historyKeymap,
        ...completionKeymap,
        ...lintKeymap,
      ]),
      latexLanguage,
      EditorView.lineWrapping,
      EditorState.readOnly.of(readOnly),
    ]

    // Add theme
    if (theme === 'dark') {
      extensions.push(oneDark)
    }

    // Add update listener
    if (onChange) {
      extensions.push(
        EditorView.updateListener.of((update) => {
          if (update.docChanged) {
            const newValue = update.state.doc.toString()
            onChange(newValue)
          }
        })
      )
    }

    // Mobile optimizations
    if ('ontouchstart' in window) {
      extensions.push(
        EditorView.domEventHandlers({
          touchstart: () => {
            // Prevent zoom on double-tap
            return false
          },
        })
      )
    }

    // Create editor state
    const state = EditorState.create({
      doc: initialContent,
      extensions,
    })

    // Create editor view
    const view = new EditorView({
      state,
      parent: editorRef.current,
    })

    viewRef.current = view
    setEditorView(view)

    // Cleanup
    return () => {
      view.destroy()
    }
  }, [readOnly, theme]) // Note: onChange and initialContent intentionally excluded

  // Update content programmatically
  const setContent = (content: string) => {
    if (!viewRef.current) return

    const transaction = viewRef.current.state.update({
      changes: {
        from: 0,
        to: viewRef.current.state.doc.length,
        insert: content,
      },
    })

    viewRef.current.dispatch(transaction)
  }

  // Get current content
  const getContent = (): string => {
    return viewRef.current?.state.doc.toString() || ''
  }

  return {
    editorRef,
    editorView,
    setContent,
    getContent,
  }
}
```

### 4.2 Editor Component

Create: `src/components/editor/Editor.tsx`

```typescript
import React, { useEffect } from 'react'
import { useCodeMirror } from '@/hooks/useCodeMirror'

interface EditorProps {
  initialContent?: string
  onChange?: (content: string) => void
  readOnly?: boolean
  theme?: 'light' | 'dark'
  className?: string
}

export const Editor: React.FC<EditorProps> = ({
  initialContent = '',
  onChange,
  readOnly = false,
  theme = 'dark',
  className = '',
}) => {
  const { editorRef, setContent } = useCodeMirror({
    initialContent,
    onChange,
    readOnly,
    theme,
  })

  // Update editor when initialContent changes from outside
  useEffect(() => {
    setContent(initialContent)
  }, [initialContent, setContent])

  return (
    <div className={`w-full h-full overflow-hidden ${className}`}>
      <div ref={editorRef} className="h-full" />
    </div>
  )
}
```

### 4.3 Editor Toolbar Component

Create: `src/components/editor/EditorToolbar.tsx`

```typescript
import React from 'react'
import {
  Bold,
  Italic,
  List,
  ListOrdered,
  Code,
  Link,
  Image,
  FileText,
  Save,
  Download,
  Settings,
} from 'lucide-react'

interface EditorToolbarProps {
  onSave?: () => void
  onDownload?: () => void
  onSettings?: () => void
  isSaving?: boolean
}

export const EditorToolbar: React.FC<EditorToolbarProps> = ({
  onSave,
  onDownload,
  onSettings,
  isSaving = false,
}) => {
  const insertCommand = (before: string, after: string = '') => {
    // This will be enhanced in Phase 4 with actual editor integration
    console.log('Insert command:', before, after)
  }

  return (
    <div className="flex items-center gap-1 px-4 py-2 bg-vscode-panel border-b border-vscode-border">
      {/* File actions */}
      <div className="flex items-center gap-1 pr-2 border-r border-vscode-border">
        <button
          onClick={onSave}
          disabled={isSaving}
          className="p-2 hover:bg-vscode-bg rounded transition-colors"
          title="Save (Ctrl+S)"
        >
          <Save className="w-4 h-4" />
        </button>
        <button
          onClick={onDownload}
          className="p-2 hover:bg-vscode-bg rounded transition-colors"
          title="Download"
        >
          <Download className="w-4 h-4" />
        </button>
      </div>

      {/* Text formatting */}
      <div className="flex items-center gap-1 pr-2 border-r border-vscode-border">
        <button
          onClick={() => insertCommand('\\textbf{', '}')}
          className="p-2 hover:bg-vscode-bg rounded transition-colors"
          title="Bold"
        >
          <Bold className="w-4 h-4" />
        </button>
        <button
          onClick={() => insertCommand('\\textit{', '}')}
          className="p-2 hover:bg-vscode-bg rounded transition-colors"
          title="Italic"
        >
          <Italic className="w-4 h-4" />
        </button>
        <button
          onClick={() => insertCommand('\\texttt{', '}')}
          className="p-2 hover:bg-vscode-bg rounded transition-colors"
          title="Code"
        >
          <Code className="w-4 h-4" />
        </button>
      </div>

      {/* Lists */}
      <div className="flex items-center gap-1 pr-2 border-r border-vscode-border">
        <button
          onClick={() => insertCommand('\\begin{itemize}\n  \\item ', '\n\\end{itemize}')}
          className="p-2 hover:bg-vscode-bg rounded transition-colors"
          title="Bullet List"
        >
          <List className="w-4 h-4" />
        </button>
        <button
          onClick={() => insertCommand('\\begin{enumerate}\n  \\item ', '\n\\end{enumerate}')}
          className="p-2 hover:bg-vscode-bg rounded transition-colors"
          title="Numbered List"
        >
          <ListOrdered className="w-4 h-4" />
        </button>
      </div>

      {/* Media */}
      <div className="flex items-center gap-1 pr-2 border-r border-vscode-border">
        <button
          onClick={() => insertCommand('\\href{url}{', '}')}
          className="p-2 hover:bg-vscode-bg rounded transition-colors"
          title="Insert Link"
        >
          <Link className="w-4 h-4" />
        </button>
        <button
          onClick={() => insertCommand('\\includegraphics{', '}')}
          className="p-2 hover:bg-vscode-bg rounded transition-colors"
          title="Insert Image"
        >
          <Image className="w-4 h-4" />
        </button>
      </div>

      {/* Spacer */}
      <div className="flex-1" />

      {/* Settings */}
      <button
        onClick={onSettings}
        className="p-2 hover:bg-vscode-bg rounded transition-colors"
        title="Settings"
      >
        <Settings className="w-4 h-4" />
      </button>
    </div>
  )
}
```

**Verification**:
```typescript
// Create test component to verify editor works
// src/pages/test/EditorTest.tsx
import { Editor } from '@/components/editor/Editor'
import { EditorToolbar } from '@/components/editor/EditorToolbar'
import { useState } from 'react'

export const EditorTest = () => {
  const [content, setContent] = useState('\\documentclass{article}\n\\begin{document}\nHello World!\n\\end{document}')

  return (
    <div className="h-screen flex flex-col">
      <EditorToolbar onSave={() => console.log('Save:', content)} />
      <Editor
        initialContent={content}
        onChange={setContent}
        theme="dark"
      />
    </div>
  )
}
```

---

## Task 5: Layout & Navigation Components (1.5 hours)

### 5.1 Main Layout

Create: `src/components/layout/MainLayout.tsx`

```typescript
import React, { ReactNode } from 'react'
import { Sidebar } from './Sidebar'
import { Header } from './Header'

interface MainLayoutProps {
  children: ReactNode
  showSidebar?: boolean
}

export const MainLayout: React.FC<MainLayoutProps> = ({
  children,
  showSidebar = true,
}) => {
  return (
    <div className="h-screen flex flex-col bg-vscode-bg text-vscode-text">
      <Header />
      <div className="flex-1 flex overflow-hidden">
        {showSidebar && <Sidebar />}
        <main className="flex-1 overflow-auto">
          {children}
        </main>
      </div>
    </div>
  )
}
```

### 5.2 Header Component

Create: `src/components/layout/Header.tsx`

```typescript
import React from 'react'
import { Link } from 'react-router-dom'
import { FileText, LogOut, User, Settings } from 'lucide-react'
import { useAuthStore } from '@/stores/authStore'
import { authService } from '@/services/authService'

export const Header: React.FC = () => {
  const { user, isAuthenticated } = useAuthStore()

  const handleLogout = async () => {
    await authService.logout()
  }

  return (
    <header className="h-12 flex items-center justify-between px-4 bg-vscode-panel border-b border-vscode-border">
      <div className="flex items-center gap-4">
        <Link to="/" className="flex items-center gap-2 hover:text-vscode-primary transition-colors">
          <FileText className="w-5 h-5" />
          <span className="font-semibold">gogotex</span>
        </Link>
      </div>

      {isAuthenticated && user && (
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2">
            <User className="w-4 h-4" />
            <span className="text-sm">{user.name || user.email}</span>
          </div>

          <Link
            to="/settings"
            className="p-2 hover:bg-vscode-bg rounded transition-colors"
            title="Settings"
          >
            <Settings className="w-4 h-4" />
          </Link>

          <button
            onClick={handleLogout}
            className="p-2 hover:bg-vscode-bg rounded transition-colors"
            title="Logout"
          >
            <LogOut className="w-4 h-4" />
          </button>
        </div>
      )}
    </header>
  )
}
```

### 5.3 Sidebar Component

Create: `src/components/layout/Sidebar.tsx`

```typescript
import React, { useState } from 'react'
import { Link, useLocation } from 'react-router-dom'
import {
  Home,
  FolderOpen,
  Users,
  Clock,
  ChevronLeft,
  ChevronRight,
} from 'lucide-react'

export const Sidebar: React.FC = () => {
  const location = useLocation()
  const [isCollapsed, setIsCollapsed] = useState(false)

  const menuItems = [
    { icon: Home, label: 'Dashboard', path: '/dashboard' },
    { icon: FolderOpen, label: 'Projects', path: '/projects' },
    { icon: Users, label: 'Shared', path: '/shared' },
    { icon: Clock, label: 'Recent', path: '/recent' },
  ]

  return (
    <aside
      className={`${
        isCollapsed ? 'w-16' : 'w-64'
      } bg-vscode-sidebar border-r border-vscode-border transition-all duration-200 flex flex-col`}
    >
      {/* Toggle button */}
      <button
        onClick={() => setIsCollapsed(!isCollapsed)}
        className="p-3 hover:bg-vscode-bg transition-colors self-end"
      >
        {isCollapsed ? (
          <ChevronRight className="w-5 h-5" />
        ) : (
          <ChevronLeft className="w-5 h-5" />
        )}
      </button>

      {/* Menu items */}
      <nav className="flex-1 py-4">
        {menuItems.map((item) => {
          const Icon = item.icon
          const isActive = location.pathname === item.path

          return (
            <Link
              key={item.path}
              to={item.path}
              className={`flex items-center gap-3 px-4 py-3 hover:bg-vscode-bg transition-colors ${
                isActive ? 'bg-vscode-bg border-l-2 border-vscode-primary' : ''
              }`}
              title={isCollapsed ? item.label : undefined}
            >
              <Icon className="w-5 h-5" />
              {!isCollapsed && <span>{item.label}</span>}
            </Link>
          )
        })}
      </nav>
    </aside>
  )
}
```

### 5.4 Loading Spinner

Create: `src/components/common/LoadingSpinner.tsx`

```typescript
import React from 'react'

interface LoadingSpinnerProps {
  size?: 'sm' | 'md' | 'lg'
  text?: string
}

export const LoadingSpinner: React.FC<LoadingSpinnerProps> = ({
  size = 'md',
  text,
}) => {
  const sizeClasses = {
    sm: 'w-4 h-4',
    md: 'w-8 h-8',
    lg: 'w-12 h-12',
  }

  return (
    <div className="flex flex-col items-center justify-center gap-3">
      <div
        className={`${sizeClasses[size]} border-4 border-vscode-border border-t-vscode-primary rounded-full animate-spin`}
      />
      {text && <p className="text-sm text-vscode-textMuted">{text}</p>}
    </div>
  )
}
```

**Verification**:
```bash
npm run dev
# Test navigation between routes
```

---

## Task 6: Authentication Pages & Flow (2 hours)

### 6.1 Login Page

Create: `src/pages/auth/LoginPage.tsx`

```typescript
import React from 'react'
import { FileText } from 'lucide-react'
import { authService } from '@/services/authService'

export const LoginPage: React.FC = () => {
  const handleLogin = () => {
    authService.redirectToLogin()
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-vscode-bg">
      <div className="max-w-md w-full px-6">
        <div className="text-center mb-8">
          <div className="flex justify-center mb-4">
            <FileText className="w-16 h-16 text-vscode-primary" />
          </div>
          <h1 className="text-3xl font-bold mb-2">gogotex</h1>
          <p className="text-vscode-textMuted">
            Collaborative LaTeX Editor
          </p>
        </div>

        <div className="card">
          <button
            onClick={handleLogin}
            className="w-full btn btn-primary"
          >
            Sign in with Keycloak
          </button>

          <p className="mt-4 text-sm text-vscode-textMuted text-center">
            By signing in, you agree to our Terms of Service and Privacy Policy
          </p>
        </div>

        <div className="mt-8 text-center text-sm text-vscode-textMuted">
          <p>New to gogotex?</p>
          <p className="mt-2">
            Contact your administrator to create an account
          </p>
        </div>
      </div>
    </div>
  )
}
```

### 6.2 OAuth Callback Page

Create: `src/pages/auth/CallbackPage.tsx`

```typescript
import React, { useEffect, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useAuthStore } from '@/stores/authStore'
import { authService } from '@/services/authService'
import { LoadingSpinner } from '@/components/common/LoadingSpinner'

export const CallbackPage: React.FC = () => {
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const setAuth = useAuthStore((state) => state.setAuth)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const handleCallback = async () => {
      try {
        const code = searchParams.get('code')
        const state = searchParams.get('state')

        if (!code || !state) {
          throw new Error('Missing authorization code or state')
        }

        // Exchange code for tokens
        const data = await authService.handleCallback(code, state)

        // Save auth data to store
        setAuth({
          user: data.user,
          accessToken: data.accessToken,
          refreshToken: data.refreshToken,
        })

        // Redirect to dashboard
        navigate('/dashboard', { replace: true })
      } catch (err) {
        console.error('Auth callback error:', err)
        setError(err instanceof Error ? err.message : 'Authentication failed')
      }
    }

    handleCallback()
  }, [searchParams, navigate, setAuth])

  if (error) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-vscode-bg">
        <div className="card max-w-md">
          <h2 className="text-xl font-bold text-vscode-error mb-4">
            Authentication Error
          </h2>
          <p className="text-vscode-textMuted mb-6">{error}</p>
          <button
            onClick={() => navigate('/login')}
            className="btn btn-primary"
          >
            Back to Login
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-vscode-bg">
      <LoadingSpinner size="lg" text="Signing you in..." />
    </div>
  )
}
```

### 6.3 Protected Route Component

Create: `src/components/common/ProtectedRoute.tsx`

```typescript
import React, { ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/stores/authStore'

interface ProtectedRouteProps {
  children: ReactNode
}

export const ProtectedRoute: React.FC<ProtectedRouteProps> = ({ children }) => {
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated)
  const location = useLocation()

  if (!isAuthenticated) {
    // Redirect to login, save current location
    return <Navigate to="/login" state={{ from: location }} replace />
  }

  return <>{children}</>
}
```

### 6.4 Dashboard Page

Create: `src/pages/dashboard/DashboardPage.tsx`

```typescript
import React from 'react'
import { Link } from 'react-router-dom'
import { Plus, FolderOpen, Users, Clock } from 'lucide-react'
import { MainLayout } from '@/components/layout/MainLayout'
import { useAuthStore } from '@/stores/authStore'

export const DashboardPage: React.FC = () => {
  const user = useAuthStore((state) => state.user)

  return (
    <MainLayout>
      <div className="p-8">
        <div className="mb-8">
          <h1 className="text-3xl font-bold mb-2">
            Welcome back, {user?.name || 'User'}!
          </h1>
          <p className="text-vscode-textMuted">
            Start collaborating on LaTeX documents
          </p>
        </div>

        {/* Quick actions */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <Link
            to="/projects/new"
            className="card hover:border-vscode-primary transition-colors cursor-pointer"
          >
            <div className="flex items-center gap-4">
              <div className="p-3 bg-vscode-primary rounded-lg">
                <Plus className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-semibold mb-1">New Project</h3>
                <p className="text-sm text-vscode-textMuted">
                  Create a new LaTeX project
                </p>
              </div>
            </div>
          </Link>

          <Link
            to="/projects"
            className="card hover:border-vscode-primary transition-colors cursor-pointer"
          >
            <div className="flex items-center gap-4">
              <div className="p-3 bg-vscode-success rounded-lg">
                <FolderOpen className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-semibold mb-1">My Projects</h3>
                <p className="text-sm text-vscode-textMuted">
                  View all your projects
                </p>
              </div>
            </div>
          </Link>

          <Link
            to="/shared"
            className="card hover:border-vscode-primary transition-colors cursor-pointer"
          >
            <div className="flex items-center gap-4">
              <div className="p-3 bg-vscode-warning rounded-lg">
                <Users className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-semibold mb-1">Shared with Me</h3>
                <p className="text-sm text-vscode-textMuted">
                  Collaborative projects
                </p>
              </div>
            </div>
          </Link>
        </div>

        {/* Recent projects placeholder */}
        <div className="card">
          <div className="flex items-center gap-3 mb-4">
            <Clock className="w-5 h-5" />
            <h2 className="text-xl font-semibold">Recent Projects</h2>
          </div>
          <p className="text-vscode-textMuted">
            No recent projects yet. Create your first project to get started!
          </p>
        </div>
      </div>
    </MainLayout>
  )
}
```

**Verification**:
```bash
# Start dev server
npm run dev

# Test flow:
# 1. Visit http://localhost:3000 → should redirect to /login
# 2. Click "Sign in with Keycloak" → redirects to Keycloak
# 3. Login with Keycloak credentials
# 4. Redirect to /auth/callback → processes tokens
# 5. Redirect to /dashboard → shows welcome page
```

---

## Task 7: Routing & App Entry Point (1 hour)

### 7.1 Router Configuration

Create: `src/App.tsx`

```typescript
import React from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { LoginPage } from './pages/auth/LoginPage'
import { CallbackPage } from './pages/auth/CallbackPage'
import { DashboardPage } from './pages/dashboard/DashboardPage'
import { ProtectedRoute } from './components/common/ProtectedRoute'
import { useAuthStore } from './stores/authStore'

function App() {
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated)

  return (
    <BrowserRouter>
      <Routes>
        {/* Public routes */}
        <Route
          path="/login"
          element={
            isAuthenticated ? <Navigate to="/dashboard" replace /> : <LoginPage />
          }
        />
        <Route path="/auth/callback" element={<CallbackPage />} />

        {/* Protected routes */}
        <Route
          path="/dashboard"
          element={
            <ProtectedRoute>
              <DashboardPage />
            </ProtectedRoute>
          }
        />

        {/* Placeholder routes for future phases */}
        <Route
          path="/projects"
          element={
            <ProtectedRoute>
              <div className="p-8">Projects page (coming in Phase 5)</div>
            </ProtectedRoute>
          }
        />
        <Route
          path="/shared"
          element={
            <ProtectedRoute>
              <div className="p-8">Shared projects (coming in Phase 5)</div>
            </ProtectedRoute>
          }
        />
        <Route
          path="/recent"
          element={
            <ProtectedRoute>
              <div className="p-8">Recent projects (coming in Phase 5)</div>
            </ProtectedRoute>
          }
        />

        {/* Default redirect */}
        <Route
          path="/"
          element={
            isAuthenticated ? (
              <Navigate to="/dashboard" replace />
            ) : (
              <Navigate to="/login" replace />
            )
          }
        />

        {/* 404 */}
        <Route path="*" element={<div className="p-8">404 Not Found</div>} />
      </Routes>
    </BrowserRouter>
  )
}

export default App
```

### 7.2 Update Main Entry

Verify: `src/main.tsx` (should already be created in Task 1)

```typescript
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.tsx'
import './styles/index.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
```

### 7.3 Update HTML Template

Update: `index.html`

```html
<!doctype html>
<html lang="en" class="dark">
  <head>
    <meta charset="UTF-8" />
    <link rel="icon" type="image/svg+xml" href="/vite.svg" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
    <meta name="description" content="Collaborative LaTeX Editor" />
    <title>gogotex - Collaborative LaTeX Editor</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

**Verification**:
```bash
npm run dev
# Test all routes manually
# Check responsive behavior (resize browser)
```

---

## Task 8: Mobile Responsiveness & Polish (1.5 hours)

### 8.1 Responsive Utilities

Create: `src/utils/responsive.ts`

```typescript
export const isMobile = (): boolean => {
  return window.innerWidth < 768
}

export const isTablet = (): boolean => {
  return window.innerWidth >= 768 && window.innerWidth < 1024
}

export const isDesktop = (): boolean => {
  return window.innerWidth >= 1024
}

export const preventZoom = (): void => {
  // Prevent pinch zoom on mobile
  document.addEventListener('gesturestart', (e) => e.preventDefault())
  document.addEventListener('gesturechange', (e) => e.preventDefault())
  document.addEventListener('gestureend', (e) => e.preventDefault())
}
```

### 8.2 Mobile-Optimized Sidebar

Update: `src/components/layout/Sidebar.tsx` (add mobile drawer)

```typescript
import React, { useState, useEffect } from 'react'
import { Link, useLocation } from 'react-router-dom'
import {
  Home,
  FolderOpen,
  Users,
  Clock,
  ChevronLeft,
  ChevronRight,
  Menu,
  X,
} from 'lucide-react'
import { isMobile } from '@/utils/responsive'

export const Sidebar: React.FC = () => {
  const location = useLocation()
  const [isCollapsed, setIsCollapsed] = useState(false)
  const [isMobileOpen, setIsMobileOpen] = useState(false)
  const [mobile, setMobile] = useState(isMobile())

  useEffect(() => {
    const handleResize = () => {
      setMobile(isMobile())
      if (!isMobile()) {
        setIsMobileOpen(false)
      }
    }

    window.addEventListener('resize', handleResize)
    return () => window.removeEventListener('resize', handleResize)
  }, [])

  const menuItems = [
    { icon: Home, label: 'Dashboard', path: '/dashboard' },
    { icon: FolderOpen, label: 'Projects', path: '/projects' },
    { icon: Users, label: 'Shared', path: '/shared' },
    { icon: Clock, label: 'Recent', path: '/recent' },
  ]

  const handleLinkClick = () => {
    if (mobile) {
      setIsMobileOpen(false)
    }
  }

  // Mobile: Drawer overlay
  if (mobile) {
    return (
      <>
        {/* Mobile menu button */}
        <button
          onClick={() => setIsMobileOpen(true)}
          className="fixed top-3 left-3 z-40 p-2 bg-vscode-panel rounded-lg lg:hidden"
        >
          <Menu className="w-6 h-6" />
        </button>

        {/* Overlay */}
        {isMobileOpen && (
          <div
            className="fixed inset-0 bg-black bg-opacity-50 z-40"
            onClick={() => setIsMobileOpen(false)}
          />
        )}

        {/* Drawer */}
        <aside
          className={`fixed top-0 left-0 h-full w-64 bg-vscode-sidebar border-r border-vscode-border z-50 transform transition-transform duration-200 ${
            isMobileOpen ? 'translate-x-0' : '-translate-x-full'
          }`}
        >
          <div className="flex items-center justify-between p-4 border-b border-vscode-border">
            <span className="font-semibold">Menu</span>
            <button onClick={() => setIsMobileOpen(false)}>
              <X className="w-5 h-5" />
            </button>
          </div>

          <nav className="py-4">
            {menuItems.map((item) => {
              const Icon = item.icon
              const isActive = location.pathname === item.path

              return (
                <Link
                  key={item.path}
                  to={item.path}
                  onClick={handleLinkClick}
                  className={`flex items-center gap-3 px-4 py-3 hover:bg-vscode-bg transition-colors ${
                    isActive ? 'bg-vscode-bg border-l-2 border-vscode-primary' : ''
                  }`}
                >
                  <Icon className="w-5 h-5" />
                  <span>{item.label}</span>
                </Link>
              )
            })}
          </nav>
        </aside>
      </>
    )
  }

  // Desktop: Standard sidebar
  return (
    <aside
      className={`${
        isCollapsed ? 'w-16' : 'w-64'
      } bg-vscode-sidebar border-r border-vscode-border transition-all duration-200 flex flex-col`}
    >
      <button
        onClick={() => setIsCollapsed(!isCollapsed)}
        className="p-3 hover:bg-vscode-bg transition-colors self-end"
      >
        {isCollapsed ? (
          <ChevronRight className="w-5 h-5" />
        ) : (
          <ChevronLeft className="w-5 h-5" />
        )}
      </button>

      <nav className="flex-1 py-4">
        {menuItems.map((item) => {
          const Icon = item.icon
          const isActive = location.pathname === item.path

          return (
            <Link
              key={item.path}
              to={item.path}
              className={`flex items-center gap-3 px-4 py-3 hover:bg-vscode-bg transition-colors ${
                isActive ? 'bg-vscode-bg border-l-2 border-vscode-primary' : ''
              }`}
              title={isCollapsed ? item.label : undefined}
            >
              <Icon className="w-5 h-5" />
              {!isCollapsed && <span>{item.label}</span>}
            </Link>
          )
        })}
      </nav>
    </aside>
  )
}
```

### 8.3 Responsive Dashboard

Update: `src/pages/dashboard/DashboardPage.tsx` (make grid responsive)

```typescript
// Change grid to responsive:
<div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 md:gap-6 mb-8">
  {/* ... cards ... */}
</div>
```

### 8.4 Package Scripts

Update: `package.json` scripts section:

```json
{
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "lint": "eslint . --ext ts,tsx --report-unused-disable-directives --max-warnings 0",
    "preview": "vite preview",
    "type-check": "tsc --noEmit"
  }
}
```

**Verification Checklist**:
- [ ] Desktop view (>1024px): Full sidebar, all features visible
- [ ] Tablet view (768-1024px): Collapsible sidebar works
- [ ] Mobile view (<768px): Drawer sidebar, hamburger menu
- [ ] Touch interactions work on mobile (editor, buttons)
- [ ] No horizontal scroll on mobile
- [ ] Text is readable without zooming
- [ ] Login flow works on mobile
- [ ] Editor is usable on mobile (though editing LaTeX on mobile is challenging)

---

## Phase 3 Completion Checklist

### Development environment (done)
- [x] Vite + React + TypeScript project created
- [x] All dependencies installed (CodeMirror, React Router, Zustand, Axios, Tailwind)
- [x] TypeScript configured with strict mode
- [x] Tailwind CSS configured and working
- [x] Path aliases (@/*) working

### Authentication (mostly done — stabilization remaining)
- [x] Auth service with Keycloak integration (backend handlers implemented)
- [x] Login page redirects to Keycloak
- [x] OAuth callback page handles authorization code
- [x] Tokens persisted (Zustand + localStorage)
- [x] Protected routes redirect to login when unauthenticated
- [x] Axios interceptor for Bearer token
- [x] Token refresh on 401 (refresh endpoint implemented)
- [x] Logout clears tokens and invokes Keycloak logout

### Backend / merged Phase‑02 (implemented; tests added)
- [x] Auth endpoints (POST `/auth/login`, `/auth/refresh`, `/auth/logout`, GET `/api/v1/me`) — `backend/go-services/handlers/auth.go`
- [x] Authorization-code exchange with Keycloak (server-side) — `/auth/login` handles code flow and token verification
- [x] Robust client auth for token exchange (client_secret_post + fallback to Basic)
- [x] JWT generation & validation tests (`internal/tokens/*`)
- [x] Session store + Redis blacklist tests (`internal/sessions/*`)
- [x] OpenAPI/Swagger docs available at `/swagger/index.html`
- [~] Integration harness & Playwright E2E (auth-code flow): scripts and tests present; CI stabilization in progress
- [~] Prebaked Playwright image (`gogotex/playwright:ci`) exists locally; CI publish job pending
- [ ] CI job to build/publish prebaked Playwright image (required)

> Test/CI guards added:
> - Playwright test now asserts the frontend POST includes `mode:"auth_code"` and logs `/auth/login` response for diagnostics.
> - Backend logs redacted outgoing token-request form and retries (helps CI troubleshooting).

### UI Components (done / verified)
- [x] CodeMirror 6 editor with LaTeX support (basic)
- [x] Editor toolbar and basic commands
- [x] Main layout with header and sidebar
- [x] Responsive sidebar (desktop/tablet/mobile)
- [x] Dashboard page with quick actions
- [x] Loading spinner component
- [x] Protected route wrapper

### Mobile Support (done)
- [x] Responsive design works on mobile (320px+)
- [x] Touch interactions implemented for core UI
- [x] Mobile drawer menu functions correctly
- [x] Editor usable on tablets (mobile caveats documented)

### Build & Deploy (done)
- [x] `npm run dev` starts development server
- [x] `npm run build` produces optimized bundle
- [x] `npm run preview` serves production build
- [x] No TypeScript errors (strict mode)
- [x] No console warnings (core flows)

---

## Remaining work & next steps (what needs to be done)

Priority 1 — Stabilize E2E & CI (must finish Phase‑03)
1. Finalize CI stabilization for auth-code E2E (required)
   - Create CI job that builds/publishes `gogotex/playwright:ci` (prebaked image).
   - Ensure `scripts/ci/auth-integration-test.sh` uses the published image and reliably starts `gogotex-auth-integration` with the latest image.
   - Acceptance: 2 consecutive green auth-code Playwright runs in CI.
   - Estimated: 1–2 days.

2. Make Playwright E2E deterministic and non‑flaky
   - Add retry/backoff for transient Keycloak `Code not valid` cases (server already retries once).
   - Harden Playwright test timeouts and explicit waits for network events.
   - Acceptance: Local 5× repeat runs succeed; CI job stable.
   - Estimated: 0.5–1 day.

Priority 2 — CI & regression guards
3. Add CI checks to prevent regressions
   - Post-build assertion that frontend bundle contains `mode:"auth_code"`.
   - Smoke test in CI that `/auth/login` returns the expected camelCase JSON keys (`accessToken`, `refreshToken`, `user`).
   - Acceptance: Build fails on regression; PR must fix before merge.
   - Estimated: 0.5 day.

Priority 3 — Polish & docs
4. Create a Phase‑03 PR and complete code review
   - Include Playwright trace artifacts, unit tests, and updated docs.
   - Acceptance: PR merged to main.
   - Estimated: 0.5–1 day (review cycle dependent).

5. Add end‑user docs / README updates
   - Document environment variables for local Keycloak + auth integration testing.
   - Document running Playwright locally with `PLAYWRIGHT_LOCAL_IMAGE`.
   - Acceptance: README updated in PR.
   - Estimated: 0.25 day.

Lower priority / future improvements
- E2E: extend Playwright to cover editor autosave / project flow.
- Add more type coverage and stricter contract tests between frontend ↔ backend.
- Add monitoring alerts for auth failures in staging.

---

## Acceptance criteria — Phase 03 complete
- Playwright auth-code flow passes reliably in CI (2 consecutive green runs).
- Frontend bundle contains required callback payload and test asserts this.
- Backend verifies and exchanges authorization codes reliably (retry + fallback present).
- PR merged and CI green.

If you want, I can now:
- create a PR with the Phase‑03 changes and run CI (recommended), or
- only update docs and leave PR creation to you.

## Troubleshooting

### Issue: "Cannot find module '@/...'"
**Solution**: Verify `tsconfig.json` has correct path aliases and restart VS Code.

### Issue: Keycloak redirect fails
**Solution**: 
- Check `VITE_KEYCLOAK_URL` in `.env`
- Verify Keycloak client configuration has correct redirect URI
- Check browser console for CORS errors

### Issue: CodeMirror editor not showing
**Solution**:
- Check parent div has defined height
- Verify all CodeMirror packages installed
- Check browser console for errors

### Issue: Tailwind styles not applying
**Solution**:
- Run `npx tailwindcss init -p` again
- Verify `tailwind.config.js` has correct content paths
- Check `src/styles/index.css` imports Tailwind directives
- Restart dev server

### Issue: Auth token not persisting
**Solution**:
- Check browser localStorage (DevTools → Application → Local Storage)
- Verify Zustand persist middleware configured correctly
- Check for browser privacy settings blocking localStorage

---

## Next Steps

**Phase 4 Preview**: Real-time Collaboration

In Phase 4, we'll add:
- WebSocket connection for real-time editing
- Yjs CRDT integration for conflict-free collaboration
- Presence awareness (see other users' cursors)
- Live document synchronization
- User activity indicators

**Estimated Duration**: 4-5 days

---

## Copilot Tips for Phase 3

1. **Use TODO comments**:
   ```typescript
   // TODO: Add LaTeX autocomplete suggestions
   // TODO: Implement spell-check integration
   // TODO: Add keyboard shortcuts modal
   ```

2. **Ask Copilot for component templates**:
   - "Create a modal component for project settings"
   - "Generate a form component for user preferences"
   - "Build a file tree component for project structure"

3. **Request optimizations**:
   - "Optimize CodeMirror for large documents"
   - "Add debouncing to onChange handler"
   - "Implement virtual scrolling for long documents"

4. **Mobile improvements**:
   - "Add swipe gestures for sidebar"
   - "Improve touch target sizes for mobile"
   - "Implement pull-to-refresh"

---

**End of Phase 3**

### Task 5: UI Components (3 hours)
- `Layout.tsx` - Main app layout (header, sidebar, content, footer)
- `Header.tsx` - Top bar with logo, user menu
- `Sidebar.tsx` - Navigation sidebar
- `Login.tsx` - Login page with Keycloak redirect
- `Dashboard.tsx` - Main dashboard after login
- `EditorView.tsx` - Editor page with CodeMirror

### Task 6: Routing (1 hour)
- Setup React Router (`react-router-dom`)
- Protected route wrapper component
- Routes: `/`, `/login`, `/callback`, `/editor/:documentId`, `/dashboard`
- Redirect logic for authenticated/unauthenticated users

### Task 7: Mobile Responsiveness (2 hours)
- Responsive layout with Tailwind breakpoints
- Mobile-friendly navigation (bottom bar)
- Touch-optimized editor controls
- Test on mobile viewport sizes

### Task 8: Docker Configuration (30 min)
- Create `docker/frontend/Dockerfile`
- Multi-stage build (build + nginx serve)
- Update `docker-compose.yml` with frontend service
- Environment variable configuration for API URLs

---

## Key Files to Create

### `frontend/vite.config.ts`
```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    host: '0.0.0.0',
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
})
```

### `frontend/src/components/Editor.tsx`
```typescript
import { useEffect, useRef } from 'react'
import { EditorView, basicSetup } from 'codemirror'
import { EditorState } from '@codemirror/state'
import { StreamLanguage } from '@codemirror/language'
import { stex } from '@codemirror/legacy-modes/mode/stex'

export function Editor({ initialContent = '', onChange }: EditorProps) {
  const editorRef = useRef<HTMLDivElement>(null)
  const viewRef = useRef<EditorView | null>(null)

  useEffect(() => {
    if (!editorRef.current) return

    // TODO: Configure CodeMirror 6 editor
    // - Setup state with LaTeX language mode
    // - Add extensions (line numbers, syntax highlighting)
    // - Configure theme (dark/light)
    // - Setup change listener for onChange callback
    // - Mobile optimizations (touch-friendly selection)

    return () => {
      viewRef.current?.destroy()
    }
  }, [])

  return <div ref={editorRef} className="editor-container" />
}
```

### `frontend/src/services/auth.ts`
```typescript
import axios from 'axios'

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:5001'

export const authService = {
  // Redirect to Keycloak login
  login: () => {
    window.location.href = `${API_URL}/auth/login`
  },

  // Exchange auth code for tokens
  exchangeCode: async (code: string) => {
    // TODO: Call /auth/login with code
    // TODO: Store tokens in localStorage
  },

  // Get current user
  getMe: async () => {
    // TODO: Call /auth/me with Bearer token
  },

  // Refresh token
  refreshToken: async (refreshToken: string) => {
    // TODO: Call /auth/refresh
  },

  // Logout
  logout: async () => {
    // TODO: Call /auth/logout
    // TODO: Clear localStorage
  },
}
```

### `frontend/src/stores/authStore.ts`
```typescript
import create from 'zustand'
import { persist } from 'zustand/middleware'

interface AuthState {
  isAuthenticated: boolean
  user: User | null
  accessToken: string | null
  refreshToken: string | null
  
  setAuth: (data: AuthData) => void
  clearAuth: () => void
  setUser: (user: User) => void
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      isAuthenticated: false,
      user: null,
      accessToken: null,
      refreshToken: null,

      setAuth: (data) => set({
        isAuthenticated: true,
        user: data.user,
        accessToken: data.accessToken,
        refreshToken: data.refreshToken,
      }),

      clearAuth: () => set({
        isAuthenticated: false,
        user: null,
        accessToken: null,
        refreshToken: null,
      }),

      setUser: (user) => set({ user }),
    }),
    { name: 'auth-storage' }
  )
)
```

---

## Completion Checklist

### Setup
- [ ] Vite project created
- [ ] All dependencies installed
- [ ] TypeScript configured
- [ ] Tailwind CSS configured
- [ ] Folder structure created

### Components
- [ ] CodeMirror 6 editor component working
- [ ] LaTeX syntax highlighting enabled
- [ ] Layout components created (Header, Sidebar, Layout)
- [ ] Login page created
- [ ] Dashboard page created
- [ ] Editor view created

### Authentication
- [ ] Auth service implemented
- [ ] Keycloak redirect flow working
- [ ] Token storage working
- [ ] Auto token refresh implemented
- [ ] Protected routes working
- [ ] Logout flow working

### Styling
- [ ] VS Code-like theme applied
- [ ] Mobile responsive (tested on small screens)
- [ ] Touch-friendly controls on mobile

### Integration
- [x] Frontend Docker container builds
- [x] Frontend starts and connects to auth service (in local compose; ensure `VITE_AUTH_URL` is set for dev)
- [ ] Can login through Keycloak
- [ ] Can view editor with LaTeX highlighting
- [ ] Can logout successfully

---

## Verification Commands

```bash
# Build frontend
cd latex-collaborative-editor/frontend
npm install
npm run build

# Start dev server
npm run dev

# Build Docker
cd ../
docker-compose build gogotex-frontend
docker-compose up -d gogotex-frontend

# Access frontend
open http://localhost:3000
```

---

## Next Phase

**Phase 4**: Real-time Collaboration (Node.js + Yjs)

Proceed to `PHASE-04-realtime-collab.md`

---

## Estimated Time

- **Minimum**: 6 hours
- **Expected**: 8-12 hours  
- **Maximum**: 3-4 days
