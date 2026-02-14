import React, { useEffect, useRef, useState } from 'react'
import Editor from '../../components/editor/Editor'
import * as Y from 'yjs'
import { WebsocketProvider } from 'y-websocket'
import { useAuthStore } from '../../stores/authStore'
import { yjsBinding } from '../../services/codemirrorYjsBinding'
import { awarenessBinding } from '../../services/codemirrorAwarenessBinding'
import { Extension } from '@codemirror/state'

export const EditorPage: React.FC = () => {
  const saved = typeof window !== 'undefined' ? localStorage.getItem('gogotex.editor.content') || '' : ''
  const [value, setValue] = useState(saved)
  const [collabEnabled, setCollabEnabled] = useState(false)
  const [extensions, setExtensions] = useState<Extension[]>([])
  const [presence, setPresence] = useState<Array<{ name: string; color?: string }>>([])
  const ytextRef = useRef<Y.Text | null>(null)
  const providerRef = useRef<any>(null)
  const editorViewRef = useRef<any>(null)
  const applyingRemoteRef = useRef(false)
  const token = useAuthStore.getState().accessToken

  useEffect(() => {
    return () => {
      // cleanup on unmount
      if (providerRef.current) try { providerRef.current.disconnect() } catch (e) { /* ignore */ }
      ytextRef.current = null
      editorViewRef.current = null
      setCollabEnabled(false)
    }
  }, [])

  const startCollab = async () => {
    if (collabEnabled) return

    const docId = 'demo-doc' // temporary demo id; later wire to real document id
    const ydoc = new Y.Doc()

    const protocol = window.location.protocol === 'https:' ? 'wss' : 'ws'
    const host = window.location.hostname || 'localhost'
    const port = 4444
    const wsUrl = `${protocol}://${host}:${port}`

    const provider = new WebsocketProvider(wsUrl, docId, ydoc, { params: { token } })
    providerRef.current = provider

    const ytext = ydoc.getText('codemirror')
    ytextRef.current = ytext

    // initialize ytext from local state if empty, otherwise adopt ytext value
    if (ytext.length === 0 && value) {
      ytext.insert(0, value)
    } else if (ytext.length > 0) {
      setValue(ytext.toString())
    }

    // create and attach CodeMirror <-> Yjs binding extension + awareness overlay
    const bindingExt = yjsBinding(ytext)
    const awarenessExt = awarenessBinding(provider.awareness)
    setExtensions((prev) => [...prev, bindingExt, awarenessExt])

    // setup awareness / presence (show user list)
    try {
      const awareness = provider.awareness
      const localUser = useAuthStore.getState().user || { name: 'Anonymous', email: 'anon' }

      const pickColor = (s: string | undefined) => {
        if (!s) return '#888'
        let h = 0
        for (let i = 0; i < s.length; i++) h = (h << 5) - h + s.charCodeAt(i)
        return `hsl(${Math.abs(h) % 360} 70% 50%)`
      }

      // store user meta (name + color)
      awareness.setLocalStateField('user', { name: localUser.name || localUser.email || 'Anonymous', color: pickColor(localUser.email) })

      const onAwarenessChange = () => {
        const states = Array.from(awareness.getStates().values()).map((s: any) => s.user).filter(Boolean)
        // dedupe by name
        const unique = Array.from(new Map(states.map((u: any) => [u.name, u])).values())
        setPresence(unique)
      }

      awareness.on('change', onAwarenessChange)
      // seed current presence
      onAwarenessChange()

      // store handler for cleanup later
      (provider as any).__awarenessHandler = onAwarenessChange
    } catch (e) {
      console.warn('awareness setup failed', e)
    }

    setCollabEnabled(true)
  }

  const stopCollab = () => {
    if (providerRef.current) {
      try {
        const handler = (providerRef.current as any).__awarenessHandler
        if (handler && providerRef.current.awareness) {
          try { providerRef.current.awareness.off('change', handler) } catch (e) { /* ignore */ }
        }
      } catch (e) { /* ignore */ }
      try { providerRef.current.disconnect() } catch (e) { /* ignore */ }
    }
    ytextRef.current = null
    providerRef.current = null
    setCollabEnabled(false)
    setPresence([])
    setExtensions([])
  }

  // Editor change handler — update Yjs when collaboration active (incremental)
  const handleChange = (v: string) => {
    setValue(v)
    try {
      if (applyingRemoteRef.current) return
      if (collabEnabled && ytextRef.current) {
        const oldStr = ytextRef.current.toString()
        if (oldStr === v) return

        // compute minimal diff (prefix/suffix)
        let start = 0
        const minLen = Math.min(oldStr.length, v.length)
        while (start < minLen && oldStr[start] === v[start]) start++

        let endOld = oldStr.length - 1
        let endNew = v.length - 1
        while (endOld >= start && endNew >= start && oldStr[endOld] === v[endNew]) {
          endOld--
          endNew--
        }

        const insert = v.slice(start, endNew + 1)
        const deleteLen = Math.max(0, endOld - start + 1)

        if (deleteLen > 0) ytextRef.current.delete(start, deleteLen)
        if (insert.length > 0) ytextRef.current.insert(start, insert)
      }
    } catch (e) {
      console.warn('Yjs incremental update failed', e)
    }
  }

  return (
    <div style={{maxWidth:960,margin:'2rem auto'}}>
      <h2>Editor (Phase‑04 — Realtime)</h2>
      <div style={{marginBottom:12}}>
        <button className="btn btn-primary" onClick={() => alert('Compile (stub)')}>Compile</button>
        <button className="btn btn-secondary" style={{marginLeft:8}} onClick={() => { navigator.clipboard?.writeText(value) }}>Copy</button>
        {!collabEnabled ? (
          <button className="btn btn-secondary" style={{marginLeft:8}} onClick={startCollab}>Enable realtime</button>
        ) : (
          <button className="btn btn-secondary" style={{marginLeft:8}} onClick={stopCollab}>Disable realtime</button>
        )}
      </div>

      <div className="card">
        <Editor initialValue={value} onChange={handleChange} extensions={extensions} onEditorReady={(v) => (editorViewRef.current = v)} />
      </div>

      <div style={{display:'flex',justifyContent:'space-between',alignItems:'center',marginTop:12}}>
        <div>
          <small>Realtime: {collabEnabled ? 'connected' : 'disconnected'}</small>
        </div>
        <div>
          <div style={{fontSize:12,color:'#666'}}>Users online:</div>
          <div className="realtime-presence" style={{display:'flex',gap:8,marginTop:4}}>
            {presence.map((p) => (
              <span key={p.name} className="presence-user" data-user={p.name} style={{background:p.color, color:'#fff', padding:'4px 8px', borderRadius:999}}>{p.name}</span>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}

export default EditorPage
