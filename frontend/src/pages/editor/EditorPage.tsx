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

    // observe remote changes and apply *incremental* updates into CodeMirror
    ytext.observe((event) => {
      try {
        if (!editorViewRef.current) return
        applyingRemoteRef.current = true
        const newText = ytext.toString()
        const oldText = editorViewRef.current.state.doc.toString()

        if (newText === oldText) return

        // compute minimal diff (prefix/suffix) and dispatch a single replace
        let start = 0
        const minLen = Math.min(oldText.length, newText.length)
        while (start < minLen && oldText[start] === newText[start]) start++

        let endOld = oldText.length - 1
        let endNew = newText.length - 1
        while (endOld >= start && endNew >= start && oldText[endOld] === newText[endNew]) {
          endOld--
          endNew--
        }

        const insert = newText.slice(start, endNew + 1)
        editorViewRef.current.dispatch({ changes: { from: start, to: endOld + 1, insert } })
        setValue(newText)
      } catch (e) {
        console.warn('apply remote ytext failed', e)
      } finally {
        applyingRemoteRef.current = false
      }
    })

    setCollabEnabled(true)
  }

  const stopCollab = () => {
    if (providerRef.current) try { providerRef.current.disconnect() } catch (e) { /* ignore */ }
    ytextRef.current = null
    providerRef.current = null
    setCollabEnabled(false)
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
        <Editor initialValue={value} onChange={handleChange} />
      </div>

      <div style={{marginTop:12}}>
        <small>Realtime: {collabEnabled ? 'connected' : 'disconnected'}</small>
      </div>
    </div>
  )
}

export default EditorPage
