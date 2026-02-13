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
}

