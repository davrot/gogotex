import { authService } from './authService'

export const editorService = {
  async syncDraft(docId: string, content: string) {
    if (!docId) throw new Error('docId required')
    const res = await authService.apiFetch(`/api/documents/${docId}`, {
      method: 'PATCH',
      body: JSON.stringify({ content }),
      headers: { 'Content-Type': 'application/json' },
    })
    if (!res.ok) {
      const t = await res.text()
      throw new Error(`syncDraft failed: ${res.status} ${t}`)
    }
    return res.json()
  },

  async createDocument(opts: { name?: string; content?: string } = {}) {
    const body = { name: opts.name ?? 'untitled.tex', content: opts.content ?? '' }
    const res = await authService.apiFetch('/api/documents', {
      method: 'POST',
      body: JSON.stringify(body),
      headers: { 'Content-Type': 'application/json' },
    })
    if (!res.ok) {
      const t = await res.text()
      throw new Error(`createDocument failed: ${res.status} ${t}`)
    }
    return res.json()
  },

  async listDocuments() {
    const res = await authService.apiFetch('/api/documents')
    if (!res.ok) {
      const t = await res.text()
      throw new Error(`listDocuments failed: ${res.status} ${t}`)
    }
    return res.json()
  },

  async getDocument(docId: string) {
    if (!docId) throw new Error('docId required')
    const res = await authService.apiFetch(`/api/documents/${docId}`)
    if (!res.ok) {
      const t = await res.text()
      throw new Error(`getDocument failed: ${res.status} ${t}`)
    }
    return res.json()
  },

  async deleteDocument(docId: string) {
    if (!docId) throw new Error('docId required')
    const res = await authService.apiFetch(`/api/documents/${docId}`, { method: 'DELETE' })
    if (!res.ok && res.status !== 204) {
      const t = await res.text()
      throw new Error(`deleteDocument failed: ${res.status} ${t}`)
    }
    return true
  },

  async compileDocument(docId: string) {
    if (!docId) throw new Error('docId required')
    const res = await authService.apiFetch(`/api/documents/${docId}/compile`, { method: 'POST' })
    if (!res.ok) {
      const t = await res.text()
      throw new Error(`compileDocument failed: ${res.status} ${t}`)
    }
    return res.json()
  },

  async getCompileLogs(docId: string) {
    if (!docId) throw new Error('docId required')
    const res = await authService.apiFetch(`/api/documents/${docId}/compile/logs`)
    if (!res.ok) {
      const t = await res.text()
      throw new Error(`getCompileLogs failed: ${res.status} ${t}`)
    }
    return res.json()
  },

  async cancelCompile(docId: string) {
    if (!docId) throw new Error('docId required')
    const res = await authService.apiFetch(`/api/documents/${docId}/compile/cancel`, { method: 'POST' })
    if (!res.ok) {
      const t = await res.text()
      throw new Error(`cancelCompile failed: ${res.status} ${t}`)
    }
    return res.json()
  },

  async getCompileSynctex(docId: string, jobId: string) {
    if (!docId || !jobId) throw new Error('docId and jobId required')
    const res = await authService.apiFetch(`/api/documents/${docId}/compile/${jobId}/synctex`)
    if (!res.ok) {
      const t = await res.text()
      throw new Error(`getCompileSynctex failed: ${res.status} ${t}`)
    }
    // return binary ArrayBuffer (gzipped SyncTeX)
    return res.arrayBuffer()
  },

  async getCompileSynctexMap(docId: string, jobId: string) {
    if (!docId || !jobId) throw new Error('docId and jobId required')
    const res = await authService.apiFetch(`/api/documents/${docId}/compile/${jobId}/synctex/map`)
    if (!res.ok) {
      const t = await res.text()
      throw new Error(`getCompileSynctexMap failed: ${res.status} ${t}`)
    }
    return res.json()
  },
}

