import React, { useRef, useState } from 'react'
import Editor, { EditorHandle } from '../../components/editor/Editor'

export const EditorPage: React.FC = () => {
  const saved = typeof window !== 'undefined' ? localStorage.getItem('gogotex.editor.content') || '' : ''
  const [value, setValue] = useState(saved)
  const editorRef = useRef<EditorHandle | null>(null)

  // when content changes: persist locally (already done by Editor) and schedule server sync
  const onEditorChange = (v: string) => {
    setValue(v)
    try { localStorage.setItem('gogotex.editor.content', v) } catch (e) {}
    scheduleSync(v)
  }

  // Open a document from server into the editor
  const openDocument = async (id: string) => {
    try {
      const svc = await import('../../services/editorService')
      const doc = await svc.editorService.getDocument(id)
      const content = (doc && doc.content) || ''
      setValue(content)
      try { localStorage.setItem('gogotex.editor.content', content); localStorage.setItem('gogotex.editor.docId', id) } catch (e) {}
      setDocId(id)
    } catch (e) {
      console.warn('openDocument failed', e)
    }
  }

  const insertBold = () => editorRef.current?.replaceSelection('\\textbf{bold}')
  const insertItalic = () => editorRef.current?.replaceSelection('\\textit{italic}')
  const insertSection = () => editorRef.current?.insertText('\\section{New section}\\n')
  const insertMath = () => editorRef.current?.replaceSelection('\\[  e^{i\\pi} + 1 = 0  \\]')
  const insertTemplate = () => editorRef.current?.insertText('% LaTeX template\\n\\documentclass{article}\\n\\begin{document}\\nHello World\\end{document}\\n')

  // Server-sync: track attached document id (persisted to localStorage)
  const [docId, setDocId] = useState<string | null>(() => {
    try {
      return typeof window !== 'undefined' ? localStorage.getItem('gogotex.editor.docId') : null
    } catch (e) { return null }
  })

  const [docName, setDocName] = useState<string>(() => {
    try { return typeof window !== 'undefined' ? (localStorage.getItem('gogotex.editor.docName') || 'untitled.tex') : 'untitled.tex' } catch (e) { return 'untitled.tex' }
  })
  const [attachIdInput, setAttachIdInput] = useState<string>('')
  const [statusMsg, setStatusMsg] = useState<{ type: 'success'|'error'|'info', text: string } | null>(null)

  const syncToServer = async (content?: string) => {
    const id = docId || (typeof window !== 'undefined' ? localStorage.getItem('gogotex.editor.docId') : null)
    if (!id) {
      // no-op if no doc id configured
      return false
    }
    try {
      const api = await import('../../services/authService')
      const body = { content: content ?? value }
      await api.authService.apiFetch(`/api/documents/${id}`, { method: 'PATCH', body: JSON.stringify(body), headers: { 'Content-Type': 'application/json' } })
      setStatusMsg({ type: 'success', text: 'Saved to server' })
      setTimeout(() => setStatusMsg(null), 2500)
      return true
    } catch (e) {
      console.warn('syncToServer failed', e)
      setStatusMsg({ type: 'error', text: 'Save failed' })
      setTimeout(() => setStatusMsg(null), 2500)
      return false
    }
  }

  // Create a new document on the server and attach it to the editor
  const createNewDocument = async () => {
    try {
      const svc = await import('../../services/editorService')
      const doc = await svc.editorService.createDocument({ name: docName || 'untitled.tex', content: value })
      const newId = (doc && (doc.id || doc._id)) || null
      if (newId) {
        try { localStorage.setItem('gogotex.editor.docId', newId); localStorage.setItem('gogotex.editor.docName', doc.name || docName) } catch (e) {}
        setDocId(newId)
        setDocName(doc.name || docName)
        setStatusMsg({ type: 'success', text: `Attached document: ${newId}` })
        setTimeout(() => setStatusMsg(null), 3000)
        return true
      }
      setStatusMsg({ type: 'error', text: 'create failed' })
      setTimeout(() => setStatusMsg(null), 3000)
      return false
    } catch (e) {
      console.warn('createNewDocument failed', e)
      setStatusMsg({ type: 'error', text: 'create failed' })
      setTimeout(() => setStatusMsg(null), 3000)
      return false
    }
  }

  const attachExisting = (id?: string) => {
    const toAttach = (id || attachIdInput || '').trim()
    if (!toAttach) {
      setStatusMsg({ type: 'error', text: 'invalid document id' })
      setTimeout(() => setStatusMsg(null), 2000)
      return
    }
    try {
      localStorage.setItem('gogotex.editor.docId', toAttach)
      setDocId(toAttach)
      setAttachIdInput('')
      setStatusMsg({ type: 'success', text: `Attached document: ${toAttach}` })
      setTimeout(() => setStatusMsg(null), 3000)
    } catch (e) {
      setStatusMsg({ type: 'error', text: 'attach failed' })
      setTimeout(() => setStatusMsg(null), 2000)
    }
  }

  // background debounce sync
  let syncTimer: any = null
  const scheduleSync = (content: string) => {
    if (syncTimer) clearTimeout(syncTimer)
    syncTimer = setTimeout(() => { void syncToServer(content) }, 1000)
  }

  return (
    <div style={{maxWidth:960,margin:'2rem auto'}}>
      <h2>Editor (Phase‑03)</h2>
      <div style={{marginBottom:8}}>
        {docId ? (
          <div className="editor-status" style={{marginBottom:6}}>Attached document: <strong>{docName || docId}</strong> <small>({docId})</small></div>
        ) : (
          <div className="editor-status" style={{marginBottom:6,color:'#666'}}>No document attached</div>
        )}
        {statusMsg && (
          <div className={`editor-toast editor-toast-${statusMsg.type}`} style={{marginTop:6, color: statusMsg.type === 'error' ? '#b00020' : '#065f46'}}>{statusMsg.text}</div>
        )}
      </div>
      <div style={{marginBottom:12}}>
        <button className="btn btn-primary" onClick={() => alert('Compile (stub)')}>Compile</button>
        <button className="btn btn-secondary" style={{marginLeft:8}} onClick={() => { navigator.clipboard?.writeText(value) }}>Copy</button>
      </div>

      <div style={{display:'flex',gap:24,alignItems:'flex-start',marginBottom:12}}>
        <div style={{width:220}}>
          {/* Document list */}
          <React.Suspense fallback={<div>Loading documents…</div>}>
            <div style={{marginBottom:12}}>
              {/* lazy-import to avoid bundle size when not used elsewhere */}
              {/* DocumentList is in components/document/DocumentList.tsx */}
            </div>
            <div style={{background:'#fafafa',padding:8,borderRadius:6}}>
              {/* Inline import to keep top-level bundle small */}
              {React.createElement((require('../../components/document/DocumentList').default as any), { onOpen: openDocument })}
            </div>
          </React.Suspense>
        </div>

        <div style={{flex:1}}>
          <div style={{display:'flex',alignItems:'center',gap:8,flexWrap:'wrap'}}>
            <input placeholder="Document name" value={docName} onChange={(e) => setDocName(e.target.value)} style={{padding:'6px 8px',borderRadius:6,border:'1px solid var(--color-border)'}} />
            <button className="btn" onClick={() => void createNewDocument()}>New document</button>
            <input placeholder="Attach doc id" value={attachIdInput} onChange={(e) => setAttachIdInput(e.target.value)} style={{padding:'6px 8px',borderRadius:6,border:'1px solid var(--color-border)', marginLeft:8}} />
            <button className="btn" onClick={() => attachExisting()}>Attach</button>

            <div style={{marginLeft:'auto',display:'flex',gap:8}}>
              <button className="btn" onClick={insertBold}>Bold</button>
              <button className="btn" style={{marginLeft:8}} onClick={insertItalic}>Italic</button>
              <button className="btn" style={{marginLeft:8}} onClick={insertSection}>Section</button>
              <button className="btn" style={{marginLeft:8}} onClick={insertMath}>Math</button>
              <button className="btn" style={{marginLeft:8}} onClick={insertTemplate}>Insert template</button>
              <button className="btn btn-secondary" style={{marginLeft:8}} onClick={() => void syncToServer()}>{docId ? `Save to server (doc: ${docId})` : 'Save to server'}</button>
            </div>
          </div>
        </div>
      </div>

      <div className="card">
        <Editor ref={editorRef} initialValue={value} onChange={onEditorChange} language="latex" onSave={() => void syncToServer()} />
      </div>
    </div>
  )
}

export default EditorPage
