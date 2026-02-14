import React, { useEffect, useRef } from 'react'
import { EditorState } from '@codemirror/state'
import { EditorView, basicSetup } from '@codemirror/basic-setup'
import { javascript } from '@codemirror/lang-javascript'

interface EditorProps {
  initialValue?: string
  onChange?: (v: string) => void
}

export const Editor: React.FC<EditorProps> = ({ initialValue = '', onChange }) => {
  const host = useRef<HTMLDivElement | null>(null)
  const viewRef = useRef<EditorView | null>(null)

  useEffect(() => {
    if (!host.current) return
    const state = EditorState.create({
      doc: initialValue,
      extensions: [
        basicSetup,
        javascript(),
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
  }, [])

  return <div className="cm-editor" ref={host} style={{minHeight: 300, border: '1px solid var(--color-border)'}} />
}

export default Editor
