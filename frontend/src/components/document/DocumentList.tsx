import React, { useEffect, useState } from 'react'
import { editorService } from '../../services/editorService'

export type DocInfo = { id: string; name: string }

const DocumentList: React.FC<{ onOpen: (id: string) => void }> = ({ onOpen }) => {
  const [docs, setDocs] = useState<DocInfo[]>([])
  const [loading, setLoading] = useState(false)

  const load = async () => {
    setLoading(true)
    try {
      const res = await editorService.listDocuments()
      setDocs(res || [])
    } catch (e) {
      setDocs([])
    } finally { setLoading(false) }
  }

  useEffect(() => { void load() }, [])

  const onRename = async (id: string, currentName: string) => {
    const name = window.prompt('New name', currentName)
    if (!name || name.trim() === '') return
    try {
      const svc = await import('../../services/editorService')
      await svc.editorService.syncDraft(id, (await svc.editorService.getDocument(id)).content || '')
      // use patch to update name
      await (await import('../../services/authService')).authService.apiFetch(`/api/documents/${id}`, { method: 'PATCH', body: JSON.stringify({ name }), headers: { 'Content-Type': 'application/json' } })
      void load()
    } catch (e) {
      console.warn('rename failed', e)
    }
  }

  const onDelete = async (id: string) => {
    if (!window.confirm('Delete document?')) return
    try {
      const svc = await import('../../services/editorService')
      await svc.editorService.deleteDocument(id)
      void load()
    } catch (e) {
      console.warn('delete failed', e)
    }
  }

  return (
    <div style={{marginBottom:12}}>
      <div style={{display:'flex',alignItems:'center',justifyContent:'space-between', marginBottom:6}}>
        <strong>Documents</strong>
        <button className="btn btn-ghost" onClick={() => void load()}>{loading ? '...' : 'Refresh'}</button>
      </div>
      {docs.length === 0 ? (
        <div style={{color:'#666'}}>No documents</div>
      ) : (
        <ul style={{paddingLeft:12}}>
          {docs.map(d => (
            <li key={d.id} style={{marginBottom:6, display: 'flex', alignItems: 'center', gap: 8}}>
              <button className="link-like" onClick={() => onOpen(d.id)}>{d.name}</button>
              <small style={{marginLeft:8,color:'#666'}}>({d.id})</small>
              <div style={{marginLeft:'auto', display:'flex', gap:8}}>
                <button className="btn btn-ghost" onClick={() => onRename(d.id, d.name)}>Rename</button>
                <button className="btn btn-ghost" onClick={() => onDelete(d.id)}>Delete</button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

export default DocumentList
