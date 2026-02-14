import React, { useEffect, useRef, useState } from 'react'
import Editor from '../../components/editor/Editor'
import * as Y from 'yjs'
import { WebsocketProvider } from 'y-websocket'
import { useAuthStore } from '../../stores/authStore'

export const EditorPage: React.FC = () => {
  const saved = typeof window !== 'undefined' ? localStorage.getItem('gogotex.editor.content') || '' : ''
  const [value, setValue] = useState(saved)
  const [collabEnabled, setCollabEnabled] = useState(false)
  const ytextRef = useRef<Y.Text | null>(null)
  const providerRef = useRef<any>(null)
  const token = useAuthStore.getState().accessToken

  useEffect(() => {
    return () => {
      // cleanup on unmount
      if (providerRef.current) try { providerRef.current.disconnect() } catch (e) { /* ignore */ }
      ytextRef.current = null
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

    // observe remote changes
    ytext.observe(() => {
      const txt = ytext.toString()
      setValue((prev) => (prev === txt ? prev : txt))
    })

    setCollabEnabled(true)
  }

  const stopCollab = () => {
    if (providerRef.current) try { providerRef.current.disconnect() } catch (e) { /* ignore */ }
    ytextRef.current = null
    providerRef.current = null
    setCollabEnabled(false)
  }

  // Editor change handler — update Yjs when collaboration active
  const handleChange = (v: string) => {
    setValue(v)
    try {
      if (collabEnabled && ytextRef.current) {
        const txt = ytextRef.current.toString()
        if (txt !== v) {
          // naive full-text replace (simple prototype)
          ytextRef.current.delete(0, txt.length)
          ytextRef.current.insert(0, v)
        }
      }
    } catch (e) {
      console.warn('Yjs update failed', e)
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
        <Editor initialValue={value} onChange={handleChange} />
      </div>

      <div style={{marginTop:12}}>
        <small>Realtime: {collabEnabled ? 'connected' : 'disconnected'}</small>
      </div>
    </div>
  )
}

export default EditorPage
