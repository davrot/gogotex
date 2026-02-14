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

  // Compile state
  const [compileStatus, setCompileStatus] = useState<'idle'|'compiling'|'ready'|'error'>('idle')
  const [compilePreviewUrl, setCompilePreviewUrl] = useState<string | null>(null)
  const [compileLogs, setCompileLogs] = useState<string | null>(null)
  const [compileJobId, setCompileJobId] = useState<string | null>(null)
  const [synctexAvailable, setSynctexAvailable] = useState<boolean>(false)
  // synctexMap: { [page: number]: Array<{ y: number, line: number }> }
  const [synctexMap, setSynctexMap] = useState<Record<number, Array<{ y: number; line: number }>> | null>(null)

  const [lastSavedAt, setLastSavedAt] = useState<number | null>(() => {
    try {
      const v = typeof window !== 'undefined' ? localStorage.getItem('gogotex.editor.lastSavedAt') : null
      return v ? parseInt(v, 10) : null
    } catch (e) { return null }
  })

  // saveStatus: small finite-state for UI save indicator (idle | queued | saving | saved | error)
  const [saveStatus, setSaveStatus] = useState<'idle'|'queued'|'saving'|'saved'|'error'>('idle')

  const persistLastSaved = (ts: number | null) => {
    setLastSavedAt(ts)
    try { if (ts) localStorage.setItem('gogotex.editor.lastSavedAt', String(ts)) } catch (e) {}
  }

  const saveQueueKey = 'gogotex.editor.saveQueue'
  const loadSaveQueue = (): Array<{ docId: string; content: string; ts: number }> => {
    try {
      const raw = localStorage.getItem(saveQueueKey)
      return raw ? JSON.parse(raw) : []
    } catch (e) { return [] }
  }
  const persistSaveQueue = (q: Array<{ docId: string; content: string; ts: number }>) => {
    try { localStorage.setItem(saveQueueKey, JSON.stringify(q)) } catch (e) {}
  }

  // enqueue: keep only the latest content per docId (collapse)
  const enqueueSave = (docIdToSave: string, content: string) => {
    const q = loadSaveQueue()
    const filtered = q.filter(it => it.docId !== docIdToSave)
    filtered.push({ docId: docIdToSave, content, ts: Date.now() })
    persistSaveQueue(filtered)
    setSaveStatus('queued')
  }

  // process queue: try to flush oldest -> newest; stop on first failure
  const processSaveQueue = async () => {
    const q = loadSaveQueue()
    if (q.length === 0) return
    for (let i = 0; i < q.length; i++) {
      const item = q[i]
      try {
        setSaveStatus('saving')
        const svc = await import('../../services/editorService')
        await svc.editorService.syncDraft(item.docId, item.content)
        // success -> remove this item and continue
        const remaining = loadSaveQueue().filter(it => it.docId !== item.docId)
        persistSaveQueue(remaining)
        persistLastSaved(Date.now())
        setSaveStatus('saved')
      } catch (e) {
        console.warn('processSaveQueue: sync failed for', item.docId, e)
        setSaveStatus('queued')
        // leave remaining queue intact and abort processing
        return
      }
    }
  }

  // Attempt immediate sync; on failure enqueue for retry
  const attemptImmediateSync = async (content?: string) => {
    const id = docId || (typeof window !== 'undefined' ? localStorage.getItem('gogotex.editor.docId') : null)
    if (!id) {
      setSaveStatus('idle')
      return false
    }
    setSaveStatus('saving')
    try {
      const svc = await import('../../services/editorService')
      await svc.editorService.syncDraft(id, content ?? value)
      persistLastSaved(Date.now())
      setSaveStatus('saved')
      return true
    } catch (e) {
      // network/error -> enqueue and schedule retry
      enqueueSave(id, content ?? value)
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
        // try flushing any queued saves for this doc
        void processSaveQueue()
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

  // Compile document (Phase‑03 stub)
  const compileDocument = async () => {
    const id = docId || (typeof window !== 'undefined' ? localStorage.getItem('gogotex.editor.docId') : null)
    if (!id) {
      setStatusMsg({ type: 'error', text: 'No document attached' })
      setTimeout(() => setStatusMsg(null), 2000)
      return
    }
    setCompileStatus('compiling')
    setCompileLogs(null)
    try {
      const svc = await import('../../services/editorService')
      const job = await svc.editorService.compileDocument(id)
      setCompileJobId(job?.jobId || null)
      // poll compile logs/status until ready or canceled
      for (let i = 0; i < 40; i++) {
        const s = await svc.editorService.getCompileLogs(id)
        setCompileLogs((s && (s.logs || '')) || null)
        if (s && s.status === 'ready') {
          setCompilePreviewUrl(s.previewUrl || `/api/documents/${id}/preview`)
          setCompileStatus('ready')
          setCompileJobId(s.jobId || null)
          // try to fetch SyncTeX (non-blocking, UI doesn't fail if missing)
          (async () => {
            try {
              const syn = await svc.editorService.getCompileSynctex(id, s.jobId)
              const arr = new Uint8Array(syn)
              const b64 = btoa(String.fromCharCode(...arr))
              try { localStorage.setItem('gogotex.editor.synctex', b64) } catch (e) { /* ignore */ }
              setSynctexAvailable(true)
            } catch (e) {
              console.warn('failed to fetch synctex', e)
            }
            // fetch best-effort SyncTeX JSON map (Phase-03 prototype)
            try {
              const map = await svc.editorService.getCompileSynctexMap(id, s.jobId)
              // normalize into numeric keys
              const pages: Record<number, Array<{ y: number; line: number }>> = {}
              if (map && map.pages) {
                for (const k of Object.keys(map.pages)) {
                  const arr = (map.pages as any)[k] as Array<any>
                  const parsed = arr.map(it => ({ y: Number(it.y), line: Number(it.line) }))
                  pages[Number(k)] = parsed
                }
              }
              setSynctexMap(pages)
            } catch (e) {
              // it's OK if map isn't present; we'll fallback to proportional mapping
              setSynctexMap(null)
            }
          })()
          return
        }
        if (s && s.status === 'canceled') {
          setCompileStatus('error')
          return
        }
        // wait a bit and poll again
        await new Promise(r => setTimeout(r, 200))
      }
      // timeout
      setCompileStatus('error')
    } catch (e) {
      console.warn('compileDocument failed', e)
      setCompileStatus('error')
    }
  }

  const cancelCompile = async () => {
    const id = docId || (typeof window !== 'undefined' ? localStorage.getItem('gogotex.editor.docId') : null)
    if (!id) return
    try {
      const svc = await import('../../services/editorService')
      await svc.editorService.cancelCompile(id)
      const s = await svc.editorService.getCompileLogs(id)
      setCompileLogs((s && (s.logs || '')) || null)
      setCompileStatus('error')
    } catch (e) {
      console.warn('cancelCompile failed', e)
      setCompileStatus('error')
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
      // attempt to flush queue for this id
      void processSaveQueue()
    } catch (e) {
      setStatusMsg({ type: 'error', text: 'attach failed' })
      setTimeout(() => setStatusMsg(null), 2000)
    }
  }

  // background debounce sync - use attemptImmediateSync so failures enqueue
  let syncTimer: any = null
  const scheduleSync = (content: string) => {
    if (syncTimer) clearTimeout(syncTimer)
    syncTimer = setTimeout(() => { void attemptImmediateSync(content) }, 1000)
  }

  // periodically try to flush queue and listen for 'online' events
  React.useEffect(() => {
    const iv = setInterval(() => { void processSaveQueue() }, 3000)
    const onOnline = () => { void processSaveQueue() }
    window.addEventListener('online', onOnline)

    // receive sync messages from preview iframe (synctex click)
    const onMessage = (ev: MessageEvent) => {
      try {
        const d = ev.data || {}
        if (d && d.type === 'synctex-click' && typeof d.line === 'number') {
          editorRef.current?.goToLine(d.line)
          return
        }
        // PDF viewer posts { type: 'pdf-click', page: n, y: 0..1 }
        if (d && d.type === 'pdf-click' && typeof d.y === 'number') {
          try {
            const page = Number(d.page || 1)
            // if we have a parsed SyncTeX map, use nearest-match; otherwise fall back to proportion
            if (synctexMap && synctexMap[page] && synctexMap[page].length > 0) {
              const list = synctexMap[page]
              let best = list[0]
              let bestDiff = Math.abs(list[0].y - d.y)
              for (let i = 1; i < list.length; i++) {
                const diff = Math.abs(list[i].y - d.y)
                if (diff < bestDiff) { bestDiff = diff; best = list[i] }
              }
              editorRef.current?.goToLine(best.line)
              return
            }
            // proportional fallback
            const txt = editorRef.current?.getValue() || ''
            const totalLines = Math.max(1, txt.split('\n').length)
            const line = Math.max(1, Math.min(totalLines, Math.round(d.y * totalLines)))
            editorRef.current?.goToLine(line)
          } catch (e) { /* ignore */ }
        }
      } catch (e) { /* ignore */ }
    }
    window.addEventListener('message', onMessage)

    // --- Realtime: subscribe to yjs-server for compile updates (auto-refresh preview / SyncTeX)
    // Connect when a document is attached; server broadcasts `{ type: 'compile-update', payload }`.
    let ws: WebSocket | null = null
    const connectRealtime = () => {
      if (!docId) return
      try {
        const defaultHost = `ws://${window.location.hostname}:1234`
        const base = (import.meta.env as any).VITE_YJS_WS_URL || defaultHost
        // connect to path matching document id so yjs-server will route broadcasts
        ws = new WebSocket(`${base}/${docId}`)
        ws.onopen = () => {
          // no-op; connection established
          console.debug('[realtime] connected', docId)
        }
        ws.onmessage = async (ev) => {
          try {
            const data = typeof ev.data === 'string' ? JSON.parse(ev.data) : null
            if (!data || data.type !== 'compile-update') return
            const payload = data.payload || {}
            const pid = payload.docId || payload.docID || payload.documentId
            if (pid && pid !== docId) return

            // update preview / job id immediately
            if (payload.previewUrl) setCompilePreviewUrl(payload.previewUrl)
            if (payload.jobId || payload.jobID) setCompileJobId(payload.jobId || payload.jobID)

            // if payload includes a synctexMap, use it directly
            const pm = payload.synctexMap || payload.synctex_map || payload.SynctexMap
            if (pm && (pm.pages || Object.keys(pm).length > 0)) {
              try {
                const pages: Record<number, Array<{ y: number; line: number }>> = {}
                const rawPages = pm.pages ?? pm
                for (const k of Object.keys(rawPages)) {
                  pages[Number(k)] = (rawPages[k] as any[]).map(it => ({ y: Number(it.y), line: Number(it.line) }))
                }
                setSynctexMap(pages)
                setSynctexAvailable(true)
                return
              } catch (e) {
                // fallthrough to try fetching
              }
            }

            // best-effort: fetch synctex map for the job if available
            try {
              const svc = await import('../../services/editorService')
              const jobId = payload.jobId || payload.jobID
              if (jobId) {
                const map = await svc.editorService.getCompileSynctexMap(docId, jobId)
                if (map && map.pages) {
                  const pages: Record<number, Array<{ y: number; line: number }>> = {}
                  for (const k of Object.keys(map.pages)) {
                    pages[Number(k)] = (map.pages as any)[k].map((it: any) => ({ y: Number(it.y), line: Number(it.line) }))
                  }
                  setSynctexMap(pages)
                  setSynctexAvailable(true)
                }
              }
            } catch (e) {
              // ignore fetch errors
            }
          } catch (e) {
            console.warn('[realtime] ws message parse error', e)
          }
        }
        ws.onclose = () => { console.debug('[realtime] ws closed', docId); ws = null }
        ws.onerror = (err) => { console.warn('[realtime] ws error', err) }
      } catch (e) {
        console.warn('[realtime] connection failed', e)
      }
    }

    // open connection immediately if docId present
    if (docId) connectRealtime()

    // try to process any existing queue on mount
    void processSaveQueue()
    return () => {
      clearInterval(iv)
      window.removeEventListener('online', onOnline)
      window.removeEventListener('message', onMessage)
      if (ws && ws.readyState === WebSocket.OPEN) {
        try { ws.close() } catch (e) { /* ignore */ }
      }
    }
  }, [docId])


  return (
    <div style={{maxWidth:960,margin:'2rem auto'}}>
      <h2>Editor (Phase‑03)</h2>
      <div style={{marginBottom:8}}>
        {docId ? (
          <div className="editor-status" style={{marginBottom:6}}>Attached document: <strong>{docName || docId}</strong> <small>({docId})</small></div>
        ) : (
          <div className="editor-status" style={{marginBottom:6,color:'#666'}}>No document attached</div>
        )}

        {/* Save indicator */}
        <div className={`save-indicator save-indicator-${saveStatus}`} style={{fontSize:12, color: saveStatus === 'error' ? '#b00020' : '#6b7280', marginTop:4}}>
          {saveStatus === 'saving' && 'Saving...'}
          {saveStatus === 'saved' && lastSavedAt && `Saved ${new Date(lastSavedAt).toLocaleTimeString()}`}
          {saveStatus === 'queued' && 'Save queued (will retry)'}
        </div>

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
              {/* Inline import to keep top-level bundle small. Use a safe require with fallback so
                  unit tests / missing module scenarios won't crash the render. */}
              {(() => {
                let DocComp: any = () => <div data-testid="doc-list-mock">No documents</div>
                try {
                  DocComp = (require('../../components/document/DocumentList').default as any)
                } catch (e) {
                  // fallback when module cannot be synchronously resolved by the test/runtime
                }
                return React.createElement(DocComp, { onOpen: openDocument })
              })()}
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
              <button className="btn" onClick={async () => {
                try {
                  const caret = (localStorage.getItem('gogotex.editor.caretLine') || '1')
                  const line = Number(caret || '1')
                  const id = docId || (localStorage.getItem('gogotex.editor.docId') || null)
                  if (!id || !compileJobId) { setStatusMsg({ type: 'error', text: 'No attached/compiled document' }); setTimeout(()=>setStatusMsg(null),2000); return }
                  const svc = await import('../../services/editorService')
                  const res = await svc.editorService.getCompileSynctexLookup(id, compileJobId, line)
                  const iframe = document.querySelector('iframe[title="preview"]') as HTMLIFrameElement | null
                  if (iframe && iframe.contentWindow) {
                    iframe.contentWindow.postMessage({ type: 'go-to', page: res.page, y: res.y }, '*')
                  }
                } catch (e) {
                  setStatusMsg({ type: 'error', text: 'Go to PDF failed' })
                  setTimeout(()=>setStatusMsg(null),2000)
                }
              }}>Go to PDF</button>
              <button className="btn btn-secondary" style={{marginLeft:8}} onClick={() => { navigator.clipboard?.writeText(value) }}>Copy</button>
              <button className="btn btn-secondary" style={{marginLeft:8}} onClick={() => void syncToServer()}>{docId ? `Save to server (doc: ${docId})` : 'Save to server'}</button>
            </div>
          </div>
        </div>
      </div>

      <div className="card">
        <Editor ref={editorRef} initialValue={value} onChange={onEditorChange} language="latex" onSave={() => void syncToServer()} />
      </div>

      {/* Compile preview area */}
      <div style={{marginTop:12}}>
        <div style={{display:'flex',alignItems:'center',gap:8}}>
          <button className="btn btn-primary" onClick={() => void compileDocument()}>Compile</button>
          {compileStatus === 'compiling' && (
            <button className="btn btn-ghost" onClick={() => void cancelCompile()}>Cancel</button>
          )}
          <div style={{fontSize:12,color:'#6b7280',display:'flex',alignItems:'center',gap:8}}>
            <div>{compileStatus === 'compiling' && 'Compiling...'}{compileStatus === 'ready' && 'Preview ready'}{compileStatus === 'error' && 'Compile failed'}</div>
            {synctexAvailable && (<div className="synctex-available" style={{fontSize:11,color:'#059669',padding:'2px 6px',borderRadius:4,background:'#ecfdf5'}}>SyncTeX available</div>)}
          </div>
        </div>
        {compileLogs && (
          <div style={{marginTop:8,background:'#0b1220',color:'#d1d5db',padding:8,borderRadius:6,fontSize:12}}>
            <pre style={{margin:0,whiteSpace:'pre-wrap'}}>{compileLogs}</pre>
          </div>
        )}
        {compilePreviewUrl && (
          <div style={{marginTop:8,border:'1px solid var(--color-border)',height:360}}>
            <iframe title="preview" src={compilePreviewUrl} style={{width:'100%',height:'100%',border:0}} />
          </div>
        )}
      </div>
    </div>
  )
}

export default EditorPage
