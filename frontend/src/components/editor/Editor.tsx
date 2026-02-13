import React, { forwardRef, useEffect, useImperativeHandle, useRef } from 'react'
import { EditorState } from '@codemirror/state'
import { EditorView, keymap } from '@codemirror/view'
import { basicSetup } from '@codemirror/basic-setup'
import { StreamLanguage } from '@codemirror/language'
import { stex } from '@codemirror/legacy-modes/mode/stex'

interface EditorProps {
  initialValue?: string
  onChange?: (v: string) => void
  language?: 'javascript' | 'latex'
}

export type EditorHandle = {
  insertText: (text: string) => void
  replaceSelection: (text: string) => void
  getValue: () => string
}

export const Editor = forwardRef<EditorHandle, EditorProps>(({ initialValue = '', onChange, language = 'latex' }, ref) => {
  const host = useRef<HTMLDivElement | null>(null)
  const viewRef = useRef<EditorView | null>(null)

  useEffect(() => {
    if (!host.current) return

    const extensions = [basicSetup]

    if (language === 'latex') {
      extensions.push(StreamLanguage.define(stex))
    }

    extensions.push(EditorView.updateListener.of((v) => {
      if (v.docChanged) {
        const val = v.state.doc.toString()
        onChange?.(val)
        try { localStorage.setItem('gogotex.editor.content', val) } catch (e) { /* ignore */ }
      }
    }))

    const state = EditorState.create({ doc: initialValue, extensions })
    viewRef.current = new EditorView({ state, parent: host.current })
    return () => { viewRef.current?.destroy(); viewRef.current = null }
  }, [language])

  useImperativeHandle(ref, () => ({
    insertText: (text: string) => {
      const v = viewRef.current
      if (!v) return
      const { from, to } = v.state.selection.main
      v.dispatch(v.state.update({ changes: { from, to, insert: text }, selection: { anchor: from + text.length } }))
      v.focus()
    },
    replaceSelection: (text: string) => {
      const v = viewRef.current
      if (!v) return
      const { from, to } = v.state.selection.main
      v.dispatch(v.state.update({ changes: { from, to, insert: text }, selection: { anchor: from + text.length } }))
      v.focus()
    },
    getValue: () => viewRef.current?.state.doc.toString() || ''
  }))

  return <div className="cm-editor" ref={host} style={{minHeight: 320, border: '1px solid var(--color-border)'}} />
})

export default Editor
