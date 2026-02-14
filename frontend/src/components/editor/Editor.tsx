import React, { useEffect, useRef } from 'react'
import { EditorState, Extension } from '@codemirror/state'
import { EditorView, basicSetup } from '@codemirror/basic-setup'
import { javascript } from '@codemirror/lang-javascript'

interface EditorProps {
  initialValue?: string
  onChange?: (v: string) => void
  extensions?: Extension[]
}

export const Editor: React.FC<EditorProps> = ({ initialValue = '', onChange, extensions = [] }) => {
  const host = useRef<HTMLDivElement | null>(null)
  const viewRef = useRef<EditorView | null>(null)

  useEffect(() => {
    if (!host.current) return
    const state = EditorState.create({
      doc: initialValue,
      extensions: [
        basicSetup,
        javascript(),
        ...extensions,
        EditorView.updateListener.of((v) => {
          if (v.docChanged) {
            const val = v.state.doc.toString()
            onChange?.(val)
            try { localStorage.setItem('gogotex.editor.content', val) } catch (e) { /* ignore */ }
          }
        }),
      ],
    })
    viewRef.current = new EditorView({ state, parent: host.current })
    return () => { viewRef.current?.destroy(); viewRef.current = null }
  }, [extensions])

  // Sync external `initialValue` into the editor without recreating the view
  useEffect(() => {
    if (!viewRef.current) return
    const current = viewRef.current.state.doc.toString()
    if (initialValue !== current) {
      viewRef.current.dispatch({ changes: { from: 0, to: current.length, insert: initialValue } })
    }
  }, [initialValue])

  return <div className="cm-editor" ref={host} style={{minHeight: 300, border: '1px solid var(--color-border)'}} />
}

export default Editor
