import React, { forwardRef, useEffect, useImperativeHandle, useRef } from 'react'
import { EditorState } from '@codemirror/state'
import { EditorView, keymap } from '@codemirror/view'
import { basicSetup } from '@codemirror/basic-setup'
import { StreamLanguage } from '@codemirror/language'
import { stex } from '@codemirror/legacy-modes/mode/stex'
import { closeBrackets } from '@codemirror/closebrackets'
import { bracketMatching } from '@codemirror/matchbrackets'
import { searchKeymap } from '@codemirror/search'

interface EditorProps {
  initialValue?: string
  onChange?: (v: string) => void
  language?: 'javascript' | 'latex'
  onSave?: () => void
}

export type EditorHandle = {
  insertText: (text: string) => void
  replaceSelection: (text: string) => void
  getValue: () => string
  goToLine: (line: number) => void
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

    // Keybindings: Ctrl/Cmd-B => bold, Ctrl/Cmd-I => italic, Ctrl/Cmd-S => save (calls onSave prop)
    extensions.push(keymap.of([
      { key: 'Mod-b', run: () => { wrapSelectionWith('\\textbf{', '}'); return true } },
      { key: 'Mod-i', run: () => { wrapSelectionWith('\\textit{', '}'); return true } },
      { key: 'Mod-s', run: () => { if (onSave) onSave(); return true } },
    ]))

    // editor quality-of-life: auto-pairing and bracket matching; search keybindings
    extensions.push(closeBrackets())
    extensions.push(bracketMatching())
    extensions.push(keymap.of(searchKeymap))

    extensions.push(EditorView.updateListener.of((v) => {
      if (v.docChanged) {
        const val = v.state.doc.toString()
        onChange?.(val)
        try { localStorage.setItem('gogotex.editor.content', val) } catch (e) { /* ignore */ }
      }
      if (v.selectionSet) {
        try {
          const line = v.state.doc.lineAt(v.state.selection.main.from).number
          localStorage.setItem('gogotex.editor.caretLine', String(line))
        } catch (e) { /* ignore */ }
      }
    }))

    // Helper to wrap current selection (defined here so keymap handlers can call it)
    function wrapSelectionWith(prefix: string, suffix: string) {
      const v = viewRef.current
      if (!v) return
      const sel = v.state.selection.main
      const selected = v.state.doc.sliceString(sel.from, sel.to)
      const insert = `${prefix}${selected || ''}${suffix}`
      v.dispatch(v.state.update({ changes: { from: sel.from, to: sel.to, insert }, selection: { anchor: sel.from + prefix.length + (selected ? selected.length : 0) } }))
      v.focus()
    }

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
    getValue: () => viewRef.current?.state.doc.toString() || '',
    goToLine: (line: number) => {
      const v = viewRef.current
      if (!v) return
      const max = v.state.doc.lines
      const target = Math.max(1, Math.min(line, max))
      const pos = v.state.doc.line(target).from
      v.dispatch(v.state.update({ selection: { anchor: pos }, scrollIntoView: true }))
      v.focus()
    }
  }))

  return <div className="cm-editor" ref={host} style={{minHeight: 320, border: '1px solid var(--color-border)'}} />
})

export default Editor
